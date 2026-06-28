//
//  LaborLog.swift
//  Out for Delivery
//
//  The per-user share root for contraction data. Every contraction relates to one
//  LaborLog so the whole labor history can be shared as a single CKShare (mom shares
//  her contraction log with a partner). Exactly one exists per user, created on first
//  launch by PersistenceController. Babies are NOT anchored here — each Baby is its
//  own independent share root (see the per-record sharing migration).
//

import Foundation
import CoreData

@objc(LaborLog)
final class LaborLog: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var contractions: NSSet?

    static func fetchRequest() -> NSFetchRequest<LaborLog> {
        NSFetchRequest<LaborLog>(entityName: "LaborLog")
    }
}
