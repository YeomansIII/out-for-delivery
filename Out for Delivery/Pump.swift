//
//  Pump.swift
//  Out for Delivery
//
//  A single pump session, scoped to a baby (Epic 9). Records volume expressed —
//  per side (left / right) or as a single combined total — plus an optional
//  session duration and note. No milk-inventory tracking is in scope.
//
//  Like Feed and Diaper, each pump is a child of its Baby (the `baby`
//  relationship), so it travels with the baby when shared. `babyID` is also kept
//  as a loose foreign key for the per-baby fetch predicate; both are set on create.
//  Optional numeric details are backed by NSNumber to preserve the nil/zero
//  distinction. Volumes are stored canonically in milliliters.
//

import Foundation
import CoreData

@objc(Pump)
final class Pump: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var babyID: UUID
    @NSManaged var timestamp: Date
    @NSManaged var note: String?

    // MARK: Caregiver attribution (who logged this session; nil for solo users).
    @NSManaged var loggedByID: String?
    @NSManaged var loggedByName: String?

    /// The baby this session belongs to (the CKShare root). Set with `babyID` on create.
    @NSManaged var baby: Baby?

    // Optional scalars stored as NSNumber so nil (not recorded) stays distinct from
    // zero. Volumes are canonical milliliters; duration is seconds.
    @NSManaged private var leftVolumeNumber: NSNumber?
    @NSManaged private var rightVolumeNumber: NSNumber?
    @NSManaged private var combinedVolumeNumber: NSNumber?
    @NSManaged private var durationNumber: NSNumber?

    static func fetchRequest() -> NSFetchRequest<Pump> {
        NSFetchRequest<Pump>(entityName: "Pump")
    }

    /// Milliliters expressed on the left side, when recorded per-side.
    var leftVolume: Double? {
        get { leftVolumeNumber?.doubleValue }
        set { leftVolumeNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Milliliters expressed on the right side, when recorded per-side.
    var rightVolume: Double? {
        get { rightVolumeNumber?.doubleValue }
        set { rightVolumeNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Milliliters expressed when entered as a single combined total (sides not split).
    var combinedVolume: Double? {
        get { combinedVolumeNumber?.doubleValue }
        set { combinedVolumeNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Session duration in seconds, when recorded.
    var duration: TimeInterval? {
        get { durationNumber?.doubleValue }
        set { durationNumber = newValue.map { NSNumber(value: $0) } }
    }

    /// Total milliliters for the session: the combined total when entered that way,
    /// otherwise the sum of the per-side amounts. nil when nothing was recorded.
    var totalVolume: Double? {
        if let combinedVolume { return combinedVolume }
        let perSide = (leftVolume ?? 0) + (rightVolume ?? 0)
        return perSide > 0 ? perSide : nil
    }

    /// One-line summary for the unified timeline (e.g. "155 ml · L 70 R 85 · 18 min",
    /// "Pump session"). Mirrors PumpRowView's detail string; reads the app-wide volume
    /// unit, so it is main-actor isolated.
    @MainActor var timelineSummary: String {
        let unit = AppState.shared.volumeUnit
        var parts: [String] = []
        if let total = totalVolume {
            parts.append(unit.formatted(fromMilliliters: total))
        }
        if combinedVolume == nil {
            var sides: [String] = []
            if let left = leftVolume { sides.append("L \(unit.inputString(fromMilliliters: left))") }
            if let right = rightVolume { sides.append("R \(unit.inputString(fromMilliliters: right))") }
            if !sides.isEmpty { parts.append(sides.joined(separator: " ")) }
        }
        if let duration { parts.append("\(Int((duration / 60).rounded())) min") }
        return parts.isEmpty ? "Pump session" : parts.joined(separator: " · ")
    }
}
