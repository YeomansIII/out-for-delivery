//
//  Contraction.swift
//  Out for Delivery
//

import Foundation
import CoreData

@objc(Contraction)
final class Contraction: NSManagedObject, Identifiable {
    // CloudKit-backed Core Data forbids unique constraints; uniqueness of `id` is
    // enforced by app logic. Non-optional properties are backed by attributes that
    // carry defaults (see PersistenceController.makeModel) so they are never nil.
    @NSManaged var id: UUID
    @NSManaged var startDate: Date
    @NSManaged var endDate: Date?
    /// User override: when true, this contraction is forced to be the first of a new
    /// session, regardless of the gap-based auto rule.
    @NSManaged var startsNewSession: Bool

    // MARK: Caregiver attribution (populated in Phase B; nil until then).
    @NSManaged var loggedByID: String?
    @NSManaged var loggedByName: String?

    /// The labor log this contraction belongs to. LaborLog is the CKShare root for
    /// contraction data; contractions are its children (cascade delete).
    @NSManaged var laborLog: LaborLog?

    static func fetchRequest() -> NSFetchRequest<Contraction> {
        NSFetchRequest<Contraction>(entityName: "Contraction")
    }

    var isInProgress: Bool { endDate == nil }
    var duration: TimeInterval? { endDate.map { $0.timeIntervalSince(startDate) } }
}
