//
//  FeedService.swift
//  Out for Delivery
//
//  Single source of truth for feed mutations (log / edit / delete), scoped to a
//  baby. Mirrors ContractionService: it routes every mutation through the one
//  shared `mainContext` (the same context SwiftUI injects for `@Query`) and, after
//  each change, re-arms the feed-on-demand reminder via FeedReminderManager.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class FeedService {
    static let shared = FeedService()

    private let context: ModelContext

    private init() {
        // Share the container's main context — the same one SwiftUI injects for
        // `@Query`. A separate context would split the object graph and let
        // deleted rows reappear on save (see ContractionService for the rationale).
        self.context = AppData.shared.container.mainContext
    }

    // MARK: - Fetch helpers

    /// All feeds for a baby, oldest first.
    func feeds(for babyID: UUID) -> [Feed] {
        let descriptor = FetchDescriptor<Feed>(
            predicate: #Predicate { $0.babyID == babyID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
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
        leftMinutes: Int? = nil,
        rightMinutes: Int? = nil
    ) -> Feed {
        let feed = Feed(
            babyID: babyID,
            timestamp: timestamp,
            kind: kind.rawValue,
            volume: volume,
            leftMinutes: leftMinutes,
            rightMinutes: rightMinutes
        )
        context.insert(feed)
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
        leftMinutes: Int?,
        rightMinutes: Int?
    ) {
        feed.timestamp = timestamp
        feed.feedKind = kind
        feed.volume = volume
        feed.leftMinutes = leftMinutes
        feed.rightMinutes = rightMinutes
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

    // MARK: - Reminder coordination

    /// Re-arms (or clears) the baby's feed-on-demand reminder after a feed change.
    func rescheduleReminder(for babyID: UUID) {
        guard let baby = baby(with: babyID) else { return }
        Task { await FeedReminderManager.shared.reschedule(for: baby) }
    }

    func baby(with id: UUID) -> Baby? {
        let descriptor = FetchDescriptor<Baby>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}

/// Pure feed-on-demand reminder timing, shared by FeedReminderManager (to schedule
/// the AlarmKit countdown) and the UI (to show "next reminder"). Kept free of
/// SwiftData / AlarmKit so it is unit-testable in isolation.
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
