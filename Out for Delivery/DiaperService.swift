//
//  DiaperService.swift
//  Out for Delivery
//
//  Single source of truth for diaper mutations (log / edit / delete), scoped to a
//  baby (Epic 10). Mirrors FeedService: every mutation routes through the one
//  shared `viewContext` (the same context SwiftUI injects for `@FetchRequest`).
//  Unlike feeds, diapers arm no reminder.
//

import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class DiaperService {
    static let shared = DiaperService()

    private let context: NSManagedObjectContext

    private init() {
        // Share the container's view context — a separate context would split the
        // object graph (see ContractionService / FeedService for the rationale).
        self.context = PersistenceController.shared.viewContext
    }

    // MARK: - Fetch helpers

    /// All diaper changes for a baby, oldest first.
    func diapers(for babyID: UUID) -> [Diaper] {
        let request = Diaper.fetchRequest()
        request.predicate = NSPredicate(format: "babyID == %@", babyID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// The most recent diaper change for a baby, if any.
    func lastDiaper(for babyID: UUID) -> Diaper? {
        diapers(for: babyID).last
    }

    /// Seconds since the most recent diaper change.
    func timeSinceLastDiaper(for babyID: UUID, now: Date = Date()) -> TimeInterval? {
        guard let last = lastDiaper(for: babyID) else { return nil }
        return now.timeIntervalSince(last.timestamp)
    }

    /// Today's wet / dirty tallies. A "both" change counts toward both totals,
    /// matching how a pediatrician asks for wet and dirty counts separately.
    func todayCounts(for babyID: UUID, now: Date = Date()) -> (wet: Int, dirty: Int) {
        let calendar = Calendar.current
        let today = diapers(for: babyID).filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let wet = today.filter(\.isWet).count
        let dirty = today.filter(\.isDirty).count
        return (wet, dirty)
    }

    // MARK: - Mutations

    /// Creates and saves a diaper change. Created only on confirm, so logging never
    /// races a sheet presentation.
    @discardableResult
    func addDiaper(
        for babyID: UUID,
        timestamp: Date = Date(),
        kind: DiaperKind,
        color: DiaperColor? = nil,
        consistency: DiaperConsistency? = nil,
        note: String? = nil
    ) -> Diaper {
        let diaper = Diaper(context: context)
        diaper.id = UUID()
        diaper.babyID = babyID
        diaper.timestamp = timestamp
        diaper.diaperKind = kind
        applyStoolDetail(to: diaper, kind: kind, color: color, consistency: consistency)
        diaper.note = note?.nonEmpty
        // The Baby is this change's share root; relate them so it travels when shared.
        diaper.baby = baby(with: babyID)
        CurrentUserIdentity.shared.stamp(diaper)
        try? context.save()
        return diaper
    }

    /// Edits a logged change's time, kind, and stool detail. Color/consistency are
    /// cleared automatically when the kind has no stool (wet).
    func update(
        _ diaper: Diaper,
        timestamp: Date,
        kind: DiaperKind,
        color: DiaperColor?,
        consistency: DiaperConsistency?,
        note: String?
    ) {
        diaper.timestamp = timestamp
        diaper.diaperKind = kind
        applyStoolDetail(to: diaper, kind: kind, color: color, consistency: consistency)
        diaper.note = note?.nonEmpty
        try? context.save()
    }

    func delete(_ diaper: Diaper) {
        context.delete(diaper)
        try? context.save()
    }

    /// Color and consistency only apply to a diaper with stool; a wet-only change
    /// clears them so a kind change can't leave orphaned detail behind.
    private func applyStoolDetail(
        to diaper: Diaper,
        kind: DiaperKind,
        color: DiaperColor?,
        consistency: DiaperConsistency?
    ) {
        diaper.diaperColor = kind.hasStool ? color : nil
        diaper.diaperConsistency = kind.hasStool ? consistency : nil
    }

    func baby(with id: UUID) -> Baby? {
        let request = Baby.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
}

extension String {
    /// nil when the string is empty or whitespace-only — keeps optional text fields
    /// genuinely nil rather than storing an empty string.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
