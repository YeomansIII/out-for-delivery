//
//  SharingManager.swift
//  Out for Delivery
//
//  Thin collaborator over NSPersistentCloudKitContainer's sharing API, keyed by
//  NSManagedObjectID so it serves any share root: a Baby (its feeds travel with it
//  as children) or the per-user LaborLog (its contractions are children). It creates
//  or fetches the CKShare rooted at a record and reads its participants for the
//  per-record sharing UI. Inviting, removing, and changing permissions happen in
//  Apple's system share sheet (presented by ShareLink); this type stays small.
//
//  Everything is @MainActor: the container, viewContext, and managed objects are all
//  main-actor bound and non-Sendable. Only Sendable values (NSManagedObjectID,
//  CKShare, CKContainer) cross any async boundary.
//

import Foundation
import CoreData
import CloudKit
import os

enum SharingError: Error {
    case recordUnavailable
    case shareFailed
}

@MainActor
final class SharingManager {
    static let shared = SharingManager()

    private init() {}

    private var container: NSPersistentCloudKitContainer { PersistenceController.shared.container }
    private var viewContext: NSManagedObjectContext { PersistenceController.shared.viewContext }

    /// The CloudKit container backing all shares (matches the persistent stack).
    /// Nonisolated so the @Sendable transfer-representation exporter can read it.
    nonisolated static var cloudKitContainer: CKContainer {
        CKContainer(identifier: PersistenceController.cloudKitContainerID)
    }

    // MARK: - Reads

    /// The existing share for a record, or nil if it isn't shared yet.
    func existingShare(forObjectID id: NSManagedObjectID) throws -> CKShare? {
        try container.fetchShares(matching: [id])[id]
    }

    /// Whether a record is currently shared.
    func isShared(_ id: NSManagedObjectID) -> Bool {
        (try? existingShare(forObjectID: id)) != nil
    }

    /// Participants of a record's share (owner + caregivers), or [] if not shared.
    func participants(forObjectID id: NSManagedObjectID) -> [CKShare.Participant] {
        (try? existingShare(forObjectID: id))?.participants ?? []
    }

    /// Whether the current user owns a record's share (vs. participates in it).
    /// Defaults to true when there is no share yet (a solo user owns their data).
    func isOwner(ofObjectID id: NSManagedObjectID) -> Bool {
        guard let share = try? existingShare(forObjectID: id),
              let me = share.currentUserParticipant else { return true }
        return me.role == .owner
    }

    // MARK: - Create / fetch share

    /// Returns the share for a record, creating one rooted at it if needed. Used by
    /// the ShareLink transfer representation's preparation handler. Bridges the
    /// completion-handler `share(_:to:)` so no managed object crosses an async
    /// boundary. Sets a friendly title for the system share sheet.
    func makeOrFetchShare(forObjectID id: NSManagedObjectID, title: String) async throws -> CKShare {
        guard let object = try? viewContext.existingObject(with: id) else {
            throw SharingError.recordUnavailable
        }
        if let existing = try? existingShare(forObjectID: id) {
            Logger.sharing.info("Reusing existing share for \(title, privacy: .public).")
            return existing
        }

        Logger.sharing.info("Creating new share for \(title, privacy: .public) (inSharedStore=\(id.persistentStore === PersistenceController.shared.sharedStore, privacy: .public)).")
        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            container.share([object], to: nil) { ids, share, _, error in
                if let share {
                    Logger.sharing.info("Share created for \(title, privacy: .public), \(ids?.count ?? 0, privacy: .public) object(s) moved to the shared zone.")
                    continuation.resume(returning: share)
                } else {
                    Logger.sharing.error("Share creation failed for \(title, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
                    continuation.resume(throwing: error ?? SharingError.shareFailed)
                }
            }
        }
        share[CKShare.SystemFieldKey.title] = title
        return share
    }

    // MARK: - Stop / leave

    /// Owner: stops sharing by deleting the share record. The record and its data
    /// stay in the owner's store; participants lose access on their next sync.
    ///
    /// Caveat: a direct CKShare delete leaves NSPersistentCloudKitContainer's local
    /// state stale, so the caller should reload (and tolerate lag) afterwards rather
    /// than assume the change is immediately reflected.
    func stopSharing(objectID id: NSManagedObjectID) async throws {
        guard let share = try existingShare(forObjectID: id) else { return }
        try await delete(share.recordID, in: Self.cloudKitContainer.privateCloudDatabase)
        Logger.sharing.info("Owner stopped sharing a record.")
    }

    /// Participant: leaves a shared record by deleting their copy of the share.
    func leaveShare(objectID id: NSManagedObjectID) async throws {
        guard let share = try existingShare(forObjectID: id) else { return }
        try await delete(share.recordID, in: Self.cloudKitContainer.sharedCloudDatabase)
        Logger.sharing.info("Participant left a shared record.")
    }

    private func delete(_ recordID: CKRecord.ID, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: recordID) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    // MARK: - Current user

    /// The current user's display name resolved from any share they participate in
    /// (the LaborLog or any Baby). nil for a solo user with no shares — attribution
    /// is informational, never required.
    func currentUserDisplayName() -> String? {
        var ids: [NSManagedObjectID] = [PersistenceController.shared.laborLog.objectID]
        ids += ((try? viewContext.fetch(Baby.fetchRequest())) ?? []).map(\.objectID)
        for id in ids {
            guard let share = try? existingShare(forObjectID: id),
                  let components = share.currentUserParticipant?.userIdentity.nameComponents else { continue }
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty { return formatted }
        }
        return nil
    }
}
