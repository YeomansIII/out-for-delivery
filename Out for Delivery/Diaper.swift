//
//  Diaper.swift
//  Out for Delivery
//
//  A single diaper change, scoped to a baby (Epic 10). The lowest-friction
//  newborn event: wet / dirty / both in as few taps as possible, with optional
//  color + consistency for a dirty diaper and an optional note. "Time since last
//  change" and today's wet/dirty counts are the clinically useful readouts.
//
//  Like Feed, each diaper is a child of its Baby (the `baby` relationship), so it
//  travels with the baby when the baby is shared as a CKShare root. `babyID` is
//  also kept as a loose foreign key so the per-baby fetch predicate stays simple;
//  both are set on create.
//

import Foundation
import CoreData

@objc(Diaper)
final class Diaper: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var babyID: UUID
    @NSManaged var timestamp: Date
    /// Raw `DiaperKind` string for CloudKit safety. Use `diaperKind` for typed access.
    @NSManaged var kind: String
    /// Raw `DiaperColor` string (dirty diapers only). nil when not recorded.
    @NSManaged var color: String?
    /// Raw `DiaperConsistency` string (dirty diapers only). nil when not recorded.
    @NSManaged var consistency: String?
    /// Optional free-text note (e.g. blood, rash).
    @NSManaged var note: String?

    // MARK: Caregiver attribution (who logged this change; nil for solo users).
    @NSManaged var loggedByID: String?
    @NSManaged var loggedByName: String?

    /// The baby this change belongs to. The Baby is the CKShare root; diapers are
    /// its children (cascade delete). Set alongside `babyID` on create.
    @NSManaged var baby: Baby?

    static func fetchRequest() -> NSFetchRequest<Diaper> {
        NSFetchRequest<Diaper>(entityName: "Diaper")
    }

    /// Typed accessor over the CloudKit-safe raw `kind` string.
    var diaperKind: DiaperKind {
        get { DiaperKind(rawValue: kind) ?? .wet }
        set { kind = newValue.rawValue }
    }

    /// Typed accessor over the raw `color` string. Only meaningful for dirty diapers.
    var diaperColor: DiaperColor? {
        get { color.flatMap(DiaperColor.init(rawValue:)) }
        set { color = newValue?.rawValue }
    }

    /// Typed accessor over the raw `consistency` string. Dirty diapers only.
    var diaperConsistency: DiaperConsistency? {
        get { consistency.flatMap(DiaperConsistency.init(rawValue:)) }
        set { consistency = newValue?.rawValue }
    }

    /// Whether this change includes stool (used for the dirty/wet daily tallies).
    var isDirty: Bool { diaperKind == .dirty || diaperKind == .both }
    /// Whether this change includes urine.
    var isWet: Bool { diaperKind == .wet || diaperKind == .both }

    /// One-line summary for the unified timeline (e.g. "Wet", "Dirty · yellow, seedy",
    /// "Both · green"). Mirrors DiaperRowView's detail string.
    var timelineSummary: String {
        var parts: [String] = []
        if let color = diaperColor { parts.append(color.label.lowercased()) }
        if let consistency = diaperConsistency { parts.append(consistency.label.lowercased()) }
        return parts.isEmpty ? diaperKind.label : "\(diaperKind.label) · \(parts.joined(separator: ", "))"
    }
}

/// What a diaper change contained. Stored as the raw string in `Diaper.kind` for
/// CloudKit safety. Color/consistency only apply when stool is present.
enum DiaperKind: String, CaseIterable, Hashable {
    case wet
    case dirty
    case both

    var label: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Both"
        }
    }

    /// SF Symbol used on tiles and rows.
    var symbolName: String {
        switch self {
        case .wet: return "drop.fill"
        case .dirty: return "tornado"
        case .both: return "drop.halffull"
        }
    }

    /// Whether color/consistency detail applies (stool present).
    var hasStool: Bool { self != .wet }
}

/// Optional stool color for a dirty diaper (Epic 10.2). Answers common pediatric
/// questions; "unknown" lets a caregiver log without committing to a color.
enum DiaperColor: String, CaseIterable, Hashable {
    case yellow
    case green
    case brown
    case black
    case red
    case unknown

    var label: String {
        switch self {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .brown: return "Brown"
        case .black: return "Black"
        case .red: return "Red"
        case .unknown: return "Not sure"
        }
    }
}

/// Optional stool consistency for a dirty diaper (Epic 10.2).
enum DiaperConsistency: String, CaseIterable, Hashable {
    case seedy
    case loose
    case firm
    case mucousy

    var label: String {
        switch self {
        case .seedy: return "Seedy"
        case .loose: return "Loose"
        case .firm: return "Firm"
        case .mucousy: return "Mucousy"
        }
    }
}
