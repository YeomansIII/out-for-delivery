//
//  Feed.swift
//  Out for Delivery
//
//  A single feeding event, scoped to a baby. "Time since last feed" is the
//  headline newborn metric, and each logged feed (re)arms the feed-on-demand
//  reminder (see FeedReminderManager).
//
//  Each feed is a child of its Baby (the `baby` relationship), so it travels with
//  the baby when the baby is shared as a CKShare root. `babyID` is also kept as a
//  loose foreign key so the per-baby fetch predicate stays simple; both are set on
//  create. Optional numeric details (bottle volume, nursing minutes) are backed by
//  NSNumber attributes to preserve the nil/zero distinction.
//

import Foundation
import CoreData

@objc(Feed)
final class Feed: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var babyID: UUID
    @NSManaged var timestamp: Date
    /// Raw `FeedKind` string for CloudKit safety. Use `feedKind` for typed access.
    @NSManaged var kind: String
    /// Optional free-text note for a feed (latch, spit-up, fussiness — story 8.11).
    @NSManaged var note: String?
    /// Raw `BottleContent` string for a bottle feed (formula vs expressed breast
    /// milk — story 8.7). nil when not recorded or not a bottle. Typed via `bottle`.
    @NSManaged var bottleContentRaw: String?

    // MARK: Caregiver attribution (who logged this feed; nil for solo users).
    @NSManaged var loggedByID: String?
    @NSManaged var loggedByName: String?

    /// The baby this feed belongs to. The Baby is the CKShare root; feeds are its
    /// children (nullify on the Baby side is a cascade, so deleting a baby deletes
    /// its feeds). Set alongside `babyID` on create.
    @NSManaged var baby: Baby?

    // Optional scalars are stored as NSNumber so nil (not recorded) stays distinct
    // from zero. The typed accessors below are the public API the app uses.
    @NSManaged private var volumeNumber: NSNumber?
    @NSManaged private var leftMinutesNumber: NSNumber?
    @NSManaged private var rightMinutesNumber: NSNumber?

    static func fetchRequest() -> NSFetchRequest<Feed> {
        NSFetchRequest<Feed>(entityName: "Feed")
    }

    /// Bottle volume in canonical milliliters (bottle feeds).
    var volume: Double? {
        get { volumeNumber?.doubleValue }
        set { volumeNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Nursing minutes on the left side (breast feeds).
    var leftMinutes: Int? {
        get { leftMinutesNumber?.intValue }
        set { leftMinutesNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Nursing minutes on the right side (breast feeds).
    var rightMinutes: Int? {
        get { rightMinutesNumber?.intValue }
        set { rightMinutesNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Typed accessor over the CloudKit-safe raw `kind` string.
    var feedKind: FeedKind {
        get { FeedKind(rawValue: kind) ?? .unspecified }
        set { kind = newValue.rawValue }
    }

    /// Typed accessor for a bottle feed's contents (formula vs expressed breast
    /// milk). Only meaningful for bottle feeds; nil when not recorded.
    var bottle: BottleContent? {
        get { bottleContentRaw.flatMap(BottleContent.init(rawValue:)) }
        set { bottleContentRaw = newValue?.rawValue }
    }

    /// Total nursing minutes across both sides (breast feeds). nil when none recorded.
    var nursingMinutes: Int? {
        let total = (leftMinutes ?? 0) + (rightMinutes ?? 0)
        return total > 0 ? total : nil
    }

    /// One-line summary for the unified timeline (e.g. "Bottle feed · 90 ml formula",
    /// "Nursing · L 10m R 8m", "Feed"). Mirrors FeedRowView's detail string; reads the
    /// app-wide volume unit, so it is main-actor isolated.
    @MainActor var timelineSummary: String {
        switch feedKind {
        case .bottle:
            var parts = ["Bottle feed"]
            if let ml = volume {
                parts.append(AppState.shared.volumeUnit.formatted(fromMilliliters: ml))
            }
            if let content = bottle {
                parts.append(content.label.lowercased())
            }
            return parts.joined(separator: " · ")
        case .breast:
            var sides: [String] = []
            if let left = leftMinutes, left > 0 { sides.append("L \(left)m") }
            if let right = rightMinutes, right > 0 { sides.append("R \(right)m") }
            return sides.isEmpty ? "Nursing" : "Nursing · " + sides.joined(separator: " ")
        case .unspecified:
            return "Feed"
        }
    }
}

/// What kind of feed this was. Bottle feeds carry a `volume`; nursing ("breast")
/// is timed (minutes per side) and gets its detailed capture with the nursing
/// stories. Stored as the raw string in `Feed.kind` for CloudKit safety.
enum FeedKind: String, CaseIterable, Hashable {
    case bottle
    case breast
    case unspecified

    var label: String {
        switch self {
        case .bottle: return "Bottle"
        case .breast: return "Breast"
        case .unspecified: return "Other"
        }
    }
}

/// What a bottle feed contained (story 8.7). Stored as the raw string in
/// `Feed.bottleContentRaw` for CloudKit safety. Applies to bottle feeds only.
enum BottleContent: String, CaseIterable, Hashable {
    case formula
    case breastMilk

    var label: String {
        switch self {
        case .formula: return "Formula"
        case .breastMilk: return "Breast milk"
        }
    }
}

/// The caregiver's preferred bottle-volume unit. Volumes are always stored in
/// milliliters (canonical) on `Feed.volume`; this only governs entry and display.
enum VolumeUnit: String, CaseIterable, Hashable {
    case milliliters
    case ounces

    var label: String {
        switch self {
        case .milliliters: return "Milliliters (ml)"
        case .ounces: return "Ounces (oz)"
        }
    }

    var abbreviation: String {
        switch self {
        case .milliliters: return "ml"
        case .ounces: return "oz"
        }
    }

    private var millilitersPerUnit: Double {
        switch self {
        case .milliliters: return 1
        case .ounces: return 29.5735
        }
    }

    func toMilliliters(_ value: Double) -> Double { value * millilitersPerUnit }
    func fromMilliliters(_ milliliters: Double) -> Double { milliliters / millilitersPerUnit }

    /// Display string for a stored (ml) volume, e.g. "90 ml" or "3.0 oz".
    func formatted(fromMilliliters milliliters: Double) -> String {
        let value = fromMilliliters(milliliters)
        switch self {
        case .milliliters: return String(format: "%.0f %@", value, abbreviation)
        case .ounces: return String(format: "%.1f %@", value, abbreviation)
        }
    }

    /// Bare number string for prefilling a text field from a stored (ml) volume.
    func inputString(fromMilliliters milliliters: Double) -> String {
        let value = fromMilliliters(milliliters)
        switch self {
        case .milliliters: return String(format: "%.0f", value)
        case .ounces: return String(format: "%.1f", value)
        }
    }
}
