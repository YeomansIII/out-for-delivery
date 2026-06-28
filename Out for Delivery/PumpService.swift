//
//  PumpService.swift
//  Out for Delivery
//
//  Single source of truth for pump-session mutations (log / edit / delete), scoped
//  to a baby (Epic 9). Mirrors FeedService: every mutation routes through the one
//  shared `viewContext`. Volumes are canonical milliliters; no reminder is armed.
//

import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class PumpService {
    static let shared = PumpService()

    private let context: NSManagedObjectContext

    private init() {
        self.context = PersistenceController.shared.viewContext
    }

    // MARK: - Fetch helpers

    /// All pump sessions for a baby, oldest first.
    func pumps(for babyID: UUID) -> [Pump] {
        let request = Pump.fetchRequest()
        request.predicate = NSPredicate(format: "babyID == %@", babyID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// The most recent pump session for a baby, if any.
    func lastPump(for babyID: UUID) -> Pump? {
        pumps(for: babyID).last
    }

    /// Seconds since the most recent pump session.
    func timeSinceLastPump(for babyID: UUID, now: Date = Date()) -> TimeInterval? {
        guard let last = lastPump(for: babyID) else { return nil }
        return now.timeIntervalSince(last.timestamp)
    }

    /// Total milliliters expressed today across all sessions — the daily figure
    /// surfaced on the dashboard.
    func todayTotalVolume(for babyID: UUID, now: Date = Date()) -> Double {
        let calendar = Calendar.current
        return pumps(for: babyID)
            .filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
            .reduce(0) { $0 + ($1.totalVolume ?? 0) }
    }

    // MARK: - Mutations

    /// Creates and saves a pump session. Created only on confirm, so logging never
    /// races a sheet presentation. Pass `combinedVolume` for a single-total entry,
    /// or `leftVolume`/`rightVolume` for a per-side entry.
    @discardableResult
    func addPump(
        for babyID: UUID,
        timestamp: Date = Date(),
        leftVolume: Double? = nil,
        rightVolume: Double? = nil,
        combinedVolume: Double? = nil,
        duration: TimeInterval? = nil,
        note: String? = nil
    ) -> Pump {
        let pump = Pump(context: context)
        pump.id = UUID()
        pump.babyID = babyID
        pump.timestamp = timestamp
        pump.leftVolume = leftVolume
        pump.rightVolume = rightVolume
        pump.combinedVolume = combinedVolume
        pump.duration = duration
        pump.note = note?.nonEmpty
        pump.baby = baby(with: babyID)
        CurrentUserIdentity.shared.stamp(pump)
        try? context.save()
        return pump
    }

    /// Edits a logged session's time, volumes, duration, and note.
    func update(
        _ pump: Pump,
        timestamp: Date,
        leftVolume: Double?,
        rightVolume: Double?,
        combinedVolume: Double?,
        duration: TimeInterval?,
        note: String?
    ) {
        pump.timestamp = timestamp
        pump.leftVolume = leftVolume
        pump.rightVolume = rightVolume
        pump.combinedVolume = combinedVolume
        pump.duration = duration
        pump.note = note?.nonEmpty
        try? context.save()
    }

    func delete(_ pump: Pump) {
        context.delete(pump)
        try? context.save()
    }

    func baby(with id: UUID) -> Baby? {
        let request = Baby.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
}
