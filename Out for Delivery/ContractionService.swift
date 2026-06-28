//
//  ContractionService.swift
//  Out for Delivery
//
//  Single source of truth for Start / Stop / Cancel / Delete.
//  Routes mutations through one `NSManagedObjectContext` and refreshes the Live Activity.
//

import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class ContractionService {
    static let shared = ContractionService()

    private let context: NSManagedObjectContext

    enum Phase: Equatable {
        case resting
        case contracting(start: Date)
    }

    private(set) var phase: Phase = .resting
    private(set) var snapshot: Snapshot = .empty

    struct Snapshot: Equatable {
        var phase: ContractionActivityAttributes.ContentState.Phase
        var currentStart: Date?
        var lastStart: Date?
        var lastDuration: TimeInterval?
        var lastInterval: TimeInterval?
        /// Total contractions ever logged. Drives the "have you used the app at all" empty state.
        var count: Int
        /// Contractions in the current session only. Drives session-scoped UI.
        var sessionCount: Int
        var avgInterval: TimeInterval?
        var avgDuration: TimeInterval?
        var patternMet: Bool

        static let empty = Snapshot(
            phase: .resting,
            currentStart: nil,
            lastStart: nil,
            lastDuration: nil,
            lastInterval: nil,
            count: 0,
            sessionCount: 0,
            avgInterval: nil,
            avgDuration: nil,
            patternMet: false
        )
    }

    private init() {
        // Share the container's view context — the same one SwiftUI injects into the
        // environment for `@FetchRequest`. Using a separate context here would split the
        // object graph: edits/deletes made on one context wouldn't be seen by the views
        // observing the other, and a later save could resurrect "deleted" rows.
        self.context = PersistenceController.shared.viewContext
        recompute()
    }

    // MARK: - Public actions

    func start() {
        guard openContraction() == nil else { return }
        let now = Date()
        let new = Contraction(context: context)
        new.id = UUID()
        new.startDate = now
        new.laborLog = PersistenceController.shared.laborLog
        CurrentUserIdentity.shared.stamp(new)
        try? context.save()
        phase = .contracting(start: now)
        recompute()
        Task { await LiveActivityManager.shared.startOrUpdate(with: snapshot) }
    }

    func stop() {
        guard let open = openContraction() else { return }
        open.endDate = Date()
        try? context.save()
        phase = .resting
        recompute()
        Task { await LiveActivityManager.shared.update(with: snapshot) }
    }

    /// "I tapped Start but it wasn't a real contraction." Deletes the open row.
    func cancelInProgress() {
        guard let open = openContraction() else { return }
        context.delete(open)
        try? context.save()
        phase = .resting
        recompute()
        Task { await LiveActivityManager.shared.update(with: snapshot) }
    }

    /// Lock Screen / Dynamic Island button entry point.
    func toggle() {
        if openContraction() == nil {
            start()
        } else {
            stop()
        }
    }

    func delete(_ contraction: Contraction) {
        let wasOpen = contraction.isInProgress
        context.delete(contraction)
        try? context.save()
        if wasOpen { phase = .resting }
        recompute()
        Task { await LiveActivityManager.shared.update(with: snapshot) }
    }

    /// Edits the start time and/or length of an existing contraction. Pass `endDate: nil`
    /// to leave (or make) the contraction in progress. Recomputes sessions and stats, since
    /// moving a start time can shift session boundaries.
    func update(_ contraction: Contraction, startDate: Date, endDate: Date?) {
        contraction.startDate = startDate
        contraction.endDate = endDate
        try? context.save()
        if endDate == nil {
            phase = .contracting(start: startDate)
        } else if openContraction() == nil {
            phase = .resting
        }
        recompute()
        Task { await LiveActivityManager.shared.update(with: snapshot) }
    }

    /// Flips the manual `startsNewSession` marker on a contraction. Only meaningful when
    /// the auto gap rule wouldn't already start a session here — callers should gate on
    /// `SessionGrouper.isManualSessionStart` or `isSessionStart` for UI affordance.
    func toggleSessionBoundary(_ contraction: Contraction) {
        contraction.startsNewSession.toggle()
        try? context.save()
        recompute()
        Task { await LiveActivityManager.shared.update(with: snapshot) }
    }

    func clearAll() {
        let all = allContractions()
        for c in all { context.delete(c) }
        try? context.save()
        phase = .resting
        recompute()
        Task { await LiveActivityManager.shared.end() }
    }

    /// Refresh from disk (e.g. after CloudKit sync brings in remote changes).
    func refresh() {
        recompute()
    }

    // MARK: - Import

    /// Bulk-imports contractions (CSV import). Entries whose start time already
    /// exists (to the second) are skipped, so re-importing the same file is
    /// idempotent. Saves once, recomputes, and refreshes the Live Activity.
    @discardableResult
    func importContractions(_ entries: [ContractionImport]) -> (imported: Int, duplicates: Int) {
        var existing = Set(allContractions().map { Self.startKey($0.startDate) })
        let laborLog = PersistenceController.shared.laborLog
        var imported = 0
        var duplicates = 0
        for entry in entries {
            let key = Self.startKey(entry.start)
            if existing.contains(key) {
                duplicates += 1
                continue
            }
            existing.insert(key)
            let c = Contraction(context: context)
            c.id = UUID()
            c.startDate = entry.start
            c.endDate = entry.end
            c.laborLog = laborLog
            CurrentUserIdentity.shared.stamp(c)
            imported += 1
        }
        if imported > 0 {
            try? context.save()
            recompute()
            Task { await LiveActivityManager.shared.update(with: snapshot) }
        }
        return (imported, duplicates)
    }

    /// De-dup key for a start time, rounded to the whole second to absorb any
    /// sub-second float drift across an export/import round trip.
    private static func startKey(_ date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate.rounded())
    }

    // MARK: - Fetch helpers

    func allContractions() -> [Contraction] {
        let request = Contraction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    private func openContraction() -> Contraction? {
        allContractions().first(where: { $0.isInProgress })
    }

    // MARK: - Snapshot

    private func recompute() {
        let all = allContractions()
        let open = all.first(where: { $0.isInProgress })

        // Stats are *always* session-scoped — between sessions, currentSession returns []
        // and everything resets cleanly until a fresh contraction starts.
        let currentSession = SessionGrouper.currentSession(from: all)
        let completedInSession = currentSession.filter { $0.endDate != nil }

        let lastCompletedInSession = completedInSession.last
        let lastStart = currentSession.last?.startDate
        let lastDuration = lastCompletedInSession?.duration

        // Most recent start-to-start interval within the current session.
        var lastInterval: TimeInterval?
        if currentSession.count >= 2 {
            lastInterval = currentSession[currentSession.count - 1].startDate
                .timeIntervalSince(currentSession[currentSession.count - 2].startDate)
        }

        let pattern = PatternAnalyzer.evaluate(all: currentSession)

        phase = open.map { .contracting(start: $0.startDate) } ?? .resting

        snapshot = Snapshot(
            phase: open == nil ? .resting : .contracting,
            currentStart: open?.startDate,
            lastStart: lastStart,
            lastDuration: lastDuration,
            lastInterval: lastInterval,
            count: all.count,
            sessionCount: currentSession.count,
            avgInterval: pattern.avgInterval,
            avgDuration: pattern.avgDuration,
            patternMet: pattern.met
        )
    }
}
