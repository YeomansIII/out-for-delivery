//
//  CKShareItem.swift
//  Out for Delivery
//
//  The Transferable wrapper ShareLink shares to invite caregivers to one record.
//  It carries only Sendable values — the record's NSManagedObjectID, a friendly
//  title, and (when already shared) the existing CKShare — so it is safe to hand to
//  the @Sendable transfer-representation exporter. We wrap the record rather than
//  conforming a non-Sendable managed object to Transferable directly. Both a Baby
//  and the LaborLog produce a CKShareItem.
//
//  When a share already exists, we present it with `.existing` so the system sheet
//  shows full management (add/remove participants, permissions, stop, leave). When
//  none exists, `.prepareShare` creates one rooted at the record, sharing its
//  hierarchy (a baby with its feeds, or the labor log with its contractions).
//

import Foundation
import CoreData
import CloudKit
import CoreTransferable

struct CKShareItem: Transferable {
    let objectID: NSManagedObjectID
    /// Friendly title for the system share sheet (e.g. the baby's name).
    let title: String
    /// The current share, if the record is already shared. nil means "not shared
    /// yet" and drives the create path.
    let existingShare: CKShare?

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            if let existing = item.existingShare {
                return .existing(existing, container: SharingManager.cloudKitContainer)
            } else {
                return .prepareShare(container: SharingManager.cloudKitContainer) {
                    try await SharingManager.shared.makeOrFetchShare(forObjectID: item.objectID, title: item.title)
                }
            }
        }
    }
}
