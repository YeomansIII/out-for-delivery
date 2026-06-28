//
//  Baby.swift
//  Out for Delivery
//
//  A baby profile. Anchors all newborn-care data and (once one exists) lets the
//  app switch between contraction-timer and newborn-tracking modes.
//

import Foundation
import CoreData

@objc(Baby)
final class Baby: NSManagedObject, Identifiable {
    // CloudKit-backed Core Data forbids unique constraints; uniqueness of `id` is
    // enforced by app logic. Non-optional properties carry model defaults so they
    // are never nil at read time.
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var birthDate: Date
    @NSManaged var isArchived: Bool
    /// When the profile was created — a stable sort key independent of birthDate.
    @NSManaged var createdAt: Date

    // MARK: Feed-on-demand reminder (per-baby)

    /// When true, logging a feed arms an AlarmKit countdown; if it lapses with no
    /// new feed, an alarm-style alert fires (overrides silent mode / Focus).
    @NSManaged var feedReminderEnabled: Bool
    /// Interval from the latest feed to the reminder. Defaults to 3 hours.
    @NSManaged var feedReminderInterval: TimeInterval
    /// The currently-scheduled AlarmKit alarm id, so it can be cancelled and
    /// rescheduled when a new feed is logged or settings change. `nil` when no
    /// reminder is armed.
    @NSManaged var feedAlarmID: UUID?

    /// This baby's feeds. The Baby is its own CKShare root, so its feeds travel
    /// with it as children (cascade delete) when the baby is shared.
    @NSManaged var feeds: NSSet?

    /// This baby's diaper changes. Children of the baby's share root (cascade delete).
    @NSManaged var diapers: NSSet?

    /// This baby's pump sessions. Children of the baby's share root (cascade delete).
    @NSManaged var pumps: NSSet?

    static func fetchRequest() -> NSFetchRequest<Baby> {
        NSFetchRequest<Baby>(entityName: "Baby")
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
