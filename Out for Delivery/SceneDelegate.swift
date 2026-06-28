//
//  SceneDelegate.swift
//  Out for Delivery
//
//  Receives an accepted CloudKit share invitation and hands its metadata to the
//  persistent container, which imports the shared record (a baby with its feeds, or
//  a labor log with its contractions) into the shared store. After import, the records
//  flow through the same viewContext and @FetchRequests as everything else, so the UI
//  needs no special-casing.
//

import UIKit
import CoreData
import CloudKit
import os

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Logger.sharing.info("userDidAcceptCloudKitShareWith fired for share \(cloudKitShareMetadata.share.recordID.recordName, privacy: .public)")
        let persistence = PersistenceController.shared
        guard let sharedStore = persistence.sharedStore else {
            Logger.sharing.error("Cannot accept share: sharedStore is nil (CloudKit not available on this device).")
            return
        }
        persistence.container.acceptShareInvitations(
            from: [cloudKitShareMetadata],
            into: sharedStore
        ) { metadatas, error in
            if let error {
                Logger.sharing.error("Failed to accept CloudKit share: \(error.localizedDescription, privacy: .public)")
                return
            }
            Logger.sharing.info("Accepted \(metadatas?.count ?? 0, privacy: .public) share invitation(s); import will follow.")
            // Imported records merge into the view context automatically. Nudge the
            // services so any open dashboards recompute, and re-resolve the current
            // user's display name now that a share exists.
            Task { @MainActor in
                ContractionService.shared.refresh()
                CurrentUserIdentity.shared.refreshName()
            }
        }
    }
}
