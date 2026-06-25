//
//  Baby.swift
//  Out for Delivery
//
//  A baby profile. Anchors all newborn-care data and (once one exists) lets the
//  app switch between contraction-timer and newborn-tracking modes.
//

import Foundation
import SwiftData

@Model
final class Baby {
    // CloudKit-backed SwiftData forbids @Attribute(.unique) and requires every
    // stored property to be optional OR have a default. Uniqueness of `id` is
    // enforced by app logic.
    var id: UUID = UUID()
    var name: String = ""
    var birthDate: Date = Date.distantPast
    var isArchived: Bool = false
    /// When the profile was created — a stable sort key independent of birthDate.
    var createdAt: Date = Date.distantPast

    // MARK: Feed-on-demand reminder (per-baby)

    /// When true, logging a feed arms an AlarmKit countdown; if it lapses with no
    /// new feed, an alarm-style alert fires (overrides silent mode / Focus).
    var feedReminderEnabled: Bool = false
    /// Interval from the latest feed to the reminder. Defaults to 3 hours.
    var feedReminderInterval: TimeInterval = 3 * 60 * 60
    /// The currently-scheduled AlarmKit alarm id, so it can be cancelled and
    /// rescheduled when a new feed is logged or settings change. `nil` when no
    /// reminder is armed.
    var feedAlarmID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        birthDate: Date,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        feedReminderEnabled: Bool = false,
        feedReminderInterval: TimeInterval = 3 * 60 * 60,
        feedAlarmID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.feedReminderEnabled = feedReminderEnabled
        self.feedReminderInterval = feedReminderInterval
        self.feedAlarmID = feedAlarmID
    }

    /// A short, human description of the baby's age, e.g. "Born today", "3 days old", "2 weeks old".
    var ageDescription: String {
        let now = Date()
        guard birthDate <= now else { return "Arriving soon" }

        let calendar = Calendar.current
        let startBirth = calendar.startOfDay(for: birthDate)
        let startNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startBirth, to: startNow).day ?? 0

        switch days {
        case 0: return "Born today"
        case 1: return "1 day old"
        case 2...13: return "\(days) days old"
        default:
            let weeks = days / 7
            let remainingDays = days % 7
            if remainingDays == 0 {
                return weeks == 1 ? "1 week old" : "\(weeks) weeks old"
            }
            return weeks == 1 ? "1 week, \(remainingDays)d old" : "\(weeks) weeks, \(remainingDays)d old"
        }
    }
}
