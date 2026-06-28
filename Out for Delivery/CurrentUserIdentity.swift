//
//  CurrentUserIdentity.swift
//  Out for Delivery
//
//  Caches the current iCloud identity so the services can stamp "who logged it"
//  (loggedByID / loggedByName) on contractions and feeds without awaiting on the
//  hot path. The stable user record name is fetched once at launch; a friendly
//  display name is resolved from any share the user participates in when one exists.
//  Solo users may have no name, which is fine: attribution is informational, never required.
//

import Foundation
import CloudKit
import Observation

/// An event that records who logged it. Contraction and Feed conform so the
/// current identity can stamp them through one path (see CurrentUserIdentity.stamp).
protocol CaregiverAttributable: AnyObject {
    var loggedByID: String? { get set }
    var loggedByName: String? { get set }
}

extension Contraction: CaregiverAttributable {}
extension Feed: CaregiverAttributable {}
extension Diaper: CaregiverAttributable {}
extension Pump: CaregiverAttributable {}

@MainActor
@Observable
final class CurrentUserIdentity {
    static let shared = CurrentUserIdentity()

    /// Stable CloudKit user record name, stamped onto events as `loggedByID`.
    private(set) var currentLoggedByID: String?
    /// Friendly display name for the current user when known (shared records
    /// only). nil for solo users.
    private(set) var currentLoggedByName: String?

    private var didWarmUp = false

    private init() {}

    /// Fetches the current iCloud identity once and resolves a display name from
    /// any share the user participates in. Safe to call repeatedly; the network
    /// fetch runs only on the first call.
    func warmUp() async {
        guard !didWarmUp else { return }
        didWarmUp = true
        if let recordID = try? await Self.userRecordID(of: SharingManager.cloudKitContainer) {
            currentLoggedByID = recordID.recordName
        }
        refreshName()
    }

    /// Stamps the current user's identity onto a freshly created event. Values may
    /// be nil for solo users, which is fine (attribution is informational). Call only
    /// on locally created objects, never on records imported from CloudKit, so a
    /// remote caregiver's attribution is preserved.
    func stamp(_ event: any CaregiverAttributable) {
        event.loggedByID = currentLoggedByID
        event.loggedByName = currentLoggedByName
    }

    /// Re-resolves the display name from any share the user participates in (the
    /// LaborLog or any Baby). Call after a share is created or accepted so newly
    /// logged events can carry a name.
    func refreshName() {
        if let name = SharingManager.shared.currentUserDisplayName() {
            currentLoggedByName = name
        }
    }

    /// Bridges the completion-handler `fetchUserRecordID` to async/await.
    private static func userRecordID(of container: CKContainer) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { id, error in
                if let id {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: error ?? CKError(.notAuthenticated))
                }
            }
        }
    }
}
