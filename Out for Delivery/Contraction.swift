//
//  Contraction.swift
//  Out for Delivery
//

import Foundation
import SwiftData

@Model
final class Contraction {
    // CloudKit-backed SwiftData forbids @Attribute(.unique) and requires every
    // stored property to be optional OR have a default. Uniqueness of `id` is
    // enforced by app logic.
    var id: UUID = UUID()
    var startDate: Date = Date.distantPast
    var endDate: Date?
    /// User override: when true, this contraction is forced to be the first of a new session,
    /// regardless of the gap-based auto rule.
    var startsNewSession: Bool = false

    init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil, startsNewSession: Bool = false) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.startsNewSession = startsNewSession
    }

    var isInProgress: Bool { endDate == nil }
    var duration: TimeInterval? { endDate.map { $0.timeIntervalSince(startDate) } }
}
