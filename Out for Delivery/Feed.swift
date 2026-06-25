//
//  Feed.swift
//  Out for Delivery
//
//  A single feeding event, scoped to a baby. "Time since last feed" is the
//  headline newborn metric, and each logged feed (re)arms the feed-on-demand
//  reminder (see FeedReminderManager).
//
//  Phase 1 logs only a timestamp. The `kind`, `volume`, and `note` fields are
//  reserved now (all optional / defaulted) so adding nursing-vs-bottle richness
//  in a later phase needs no CloudKit schema migration.
//

import Foundation
import SwiftData

@Model
final class Feed {
    // CloudKit-backed SwiftData forbids @Attribute(.unique) and requires every
    // stored property to be optional OR have a default. Uniqueness of `id` is
    // enforced by app logic; `babyID` scopes the feed to its Baby.
    var id: UUID = UUID()
    var babyID: UUID = UUID()
    var timestamp: Date = Date.distantPast
    /// Reserved for a later phase (nursing / bottle). Raw string for CloudKit safety.
    var kind: String = "unspecified"
    /// Bottle volume in canonical milliliters (bottle feeds).
    var volume: Double?
    /// Nursing minutes on the left side (breast feeds).
    var leftMinutes: Int?
    /// Nursing minutes on the right side (breast feeds).
    var rightMinutes: Int?
    /// Reserved for a later phase (per-feed note).
    var note: String?

    init(
        id: UUID = UUID(),
        babyID: UUID,
        timestamp: Date = Date(),
        kind: String = "unspecified",
        volume: Double? = nil,
        leftMinutes: Int? = nil,
        rightMinutes: Int? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.babyID = babyID
        self.timestamp = timestamp
        self.kind = kind
        self.volume = volume
        self.leftMinutes = leftMinutes
        self.rightMinutes = rightMinutes
        self.note = note
    }

    /// Typed accessor over the CloudKit-safe raw `kind` string.
    var feedKind: FeedKind {
        get { FeedKind(rawValue: kind) ?? .unspecified }
        set { kind = newValue.rawValue }
    }

    /// Total nursing minutes across both sides (breast feeds). nil when none recorded.
    var nursingMinutes: Int? {
        let total = (leftMinutes ?? 0) + (rightMinutes ?? 0)
        return total > 0 ? total : nil
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
