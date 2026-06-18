//
//  ContractionService.swift
//  Out for Delivery
//
//  Single source of truth for Start / Stop / Cancel / Delete.
//  Routes mutations through one `ModelContext` and refreshes the Live Activity.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ContractionService {
    static let shared = ContractionService()

    private let container: ModelContainer
    private let context: ModelContext

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
        self.container = AppData.shared.container
        // Share the container's main context — the same one SwiftUI injects into the
        // environment for `@Query`. Using a separate context here would split the object
        // graph: edits/deletes made on one context wouldn't be seen by the views observing
        // the other, and a later save could resurrect "deleted" rows from the store.
        self.context = container.mainContext
        recompute()
    }

    // MARK: - Public actions

    func start() {
        guard openContraction() == nil else { return }
        let now = Date()
        let new = Contraction(startDate: now)
        context.insert(new)
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

    // MARK: - Fetch helpers

    func allContractions() -> [Contraction] {
        let descriptor = FetchDescriptor<Contraction>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
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
