//
//  FeedService.swift
//  Out for Delivery
//
//  Single source of truth for feed mutations (log / edit / delete), scoped to a
//  baby. Mirrors ContractionService: it routes every mutation through the one
//  shared `viewContext` (the same context SwiftUI injects for `@FetchRequest`) and,
//  after each change, re-arms the feed-on-demand reminder via FeedReminderManager.
//

import Foundation
import CoreData
import Observation

@MainActor
@Observable
final class FeedService {
    static let shared = FeedService()

    private let context: NSManagedObjectContext

    private init() {
        // Share the container's view context — the same one SwiftUI injects for
        // `@FetchRequest`. A separate context would split the object graph and let
        // deleted rows reappear on save (see ContractionService for the rationale).
        self.context = PersistenceController.shared.viewContext
    }

    // MARK: - Fetch helpers

    /// All feeds for a baby, oldest first.
    func feeds(for babyID: UUID) -> [Feed] {
        let request = Feed.fetchRequest()
        request.predicate = NSPredicate(format: "babyID == %@", babyID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// The most recent feed for a baby, if any.
    func lastFeed(for babyID: UUID) -> Feed? {
        feeds(for: babyID).last
    }

    /// Seconds since the most recent feed — the headline newborn metric.
    func timeSinceLastFeed(for babyID: UUID, now: Date = Date()) -> TimeInterval? {
        guard let last = lastFeed(for: babyID) else { return nil }
        return now.timeIntervalSince(last.timestamp)
    }

    // MARK: - Mutations

    /// Creates and saves a feed with the given details, then re-arms the reminder.
    /// Returns the new feed. Created only when the caregiver confirms, so logging
    /// never races a sheet presentation.
    @discardableResult
    func addFeed(
        for babyID: UUID,
        timestamp: Date = Date(),
        kind: FeedKind = .unspecified,
        volume: Double? = nil,
        bottle: BottleContent? = nil,
        leftMinutes: Int? = nil,
        rightMinutes: Int? = nil,
        note: String? = nil
    ) -> Feed {
        let feed = Feed(context: context)
        feed.id = UUID()
        feed.babyID = babyID
        feed.timestamp = timestamp
        feed.feedKind = kind
        feed.volume = volume
        feed.bottle = bottle
        feed.leftMinutes = leftMinutes
        feed.rightMinutes = rightMinutes
        feed.note = note?.nonEmpty
        // The Baby is this feed's share root; relate them so the feed travels with
        // the baby when shared. babyID stays set for the per-baby fetch predicate.
        feed.baby = baby(with: babyID)
        CurrentUserIdentity.shared.stamp(feed)
        try? context.save()
        rescheduleReminder(for: babyID)
        return feed
    }

    /// Edits a logged feed's time, kind, and per-kind detail: bottle `volume`
    /// (ml, canonical) and breast nursing minutes per side. Pass `nil` for fields
    /// that don't apply to the chosen kind.
    func update(
        _ feed: Feed,
        timestamp: Date,
        kind: FeedKind,
        volume: Double?,
        bottle: BottleContent?,
        leftMinutes: Int?,
        rightMinutes: Int?,
        note: String?
    ) {
        feed.timestamp = timestamp
        feed.feedKind = kind
        feed.volume = volume
        feed.bottle = bottle
        feed.leftMinutes = leftMinutes
        feed.rightMinutes = rightMinutes
        feed.note = note?.nonEmpty
        try? context.save()
        rescheduleReminder(for: feed.babyID)
    }

    func delete(_ feed: Feed) {
        let babyID = feed.babyID
        context.delete(feed)
        try? context.save()
        rescheduleReminder(for: babyID)
    }

    /// Persist external mutations made to a managed object in the shared context —
    /// e.g. FeedReminderManager writing `Baby.feedAlarmID`, or a settings change.
    func save() {
        try? context.save()
    }

    // MARK: - Import

    /// Bulk-imports feeds for one baby (CSV import). Records whose (timestamp, kind)
    /// already exists are skipped, so re-importing the same file is idempotent.
    /// Saves once and re-arms the reminder a single time afterwards.
    @discardableResult
    func importFeeds(for babyID: UUID, records: [FeedImport]) -> (imported: Int, duplicates: Int) {
        var existing = Set(feeds(for: babyID).map { Self.feedKey(timestamp: $0.timestamp, kind: $0.kind) })
        let baby = baby(with: babyID)
        var imported = 0
        var duplicates = 0
        for record in records {
            let key = Self.feedKey(timestamp: record.timestamp, kind: record.kind.rawValue)
            if existing.contains(key) {
                duplicates += 1
                continue
            }
            existing.insert(key)
            let feed = Feed(context: context)
            feed.id = UUID()
            feed.babyID = babyID
            feed.timestamp = record.timestamp
            feed.feedKind = record.kind
            feed.volume = record.volume
            feed.leftMinutes = record.leftMinutes
            feed.rightMinutes = record.rightMinutes
            feed.note = record.note
            feed.baby = baby
            CurrentUserIdentity.shared.stamp(feed)
            imported += 1
        }
        if imported > 0 {
            try? context.save()
            rescheduleReminder(for: babyID)
        }
        return (imported, duplicates)
    }

    /// De-dup key for a feed, rounding the timestamp to the whole second to absorb
    /// any sub-second float drift across an export/import round trip.
    private static func feedKey(timestamp: Date, kind: String) -> String {
        "\(Int(timestamp.timeIntervalSinceReferenceDate.rounded()))-\(kind)"
    }

    // MARK: - Reminder coordination

    /// Re-arms (or clears) the baby's feed-on-demand reminder after a feed change.
    func rescheduleReminder(for babyID: UUID) {
        guard let baby = baby(with: babyID) else { return }
        Task { await FeedReminderManager.shared.reschedule(for: baby) }
    }

    func baby(with id: UUID) -> Baby? {
        let request = Baby.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
}

/// Pure feed-on-demand reminder timing, shared by FeedReminderManager (to schedule
/// the AlarmKit countdown) and the UI (to show "next reminder"). Kept free of
/// Core Data / AlarmKit so it is unit-testable in isolation.
enum FeedMath {
    /// When the reminder should fire: (last feed, or now if none) + interval.
    static func reminderFireDate(lastFeed: Date?, interval: TimeInterval, now: Date = Date()) -> Date {
        (lastFeed ?? now).addingTimeInterval(interval)
    }

    /// Seconds from `now` until the reminder fires, clamped to at least `minimum`
    /// (AlarmKit countdowns need a positive duration, and an overdue feed should
    /// alert almost immediately rather than be skipped).
    static func remainingUntilFire(
        lastFeed: Date?,
        interval: TimeInterval,
        now: Date = Date(),
        minimum: TimeInterval = 1
    ) -> TimeInterval {
        max(minimum, reminderFireDate(lastFeed: lastFeed, interval: interval, now: now).timeIntervalSince(now))
    }
}
