//
//  PersistenceController.swift
//  Out for Delivery
//
//  Single CloudKit-backed Core Data stack (NSPersistentCloudKitContainer).
//  Replaces the SwiftData AppData stack. Exposes ONE viewContext shared by the
//  app's environment, ContractionService, and FeedService — the same
//  single-context discipline the SwiftData version relied on (a second context
//  would split the object graph and let deleted rows reappear on save).
//
//  The managed object model is built in code (see makeModel) rather than from an
//  .xcdatamodeld bundle, so the whole schema is version-controlled Swift and needs
//  no Xcode model-editor step. NSPersistentCloudKitContainer mirrors a programmatic
//  model to CloudKit the same way it does a bundled one.
//
//  Phase A stands up the private CloudKit store only and is behavior-preserving.
//  The second (.shared) store and the CKShare invite/accept flow come in Phase B.
//

import Foundation
import CoreData
import CloudKit
import os

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    /// In-memory stack for SwiftUI previews and tests.
    static let preview = PersistenceController(inMemory: true)

    let container: NSPersistentCloudKitContainer

    /// The single context everything uses (app environment + both services).
    var viewContext: NSManagedObjectContext { container.viewContext }

    /// The app's CloudKit container, matching `Out_for_Delivery.entitlements`.
    static let cloudKitContainerID = "iCloud.us.yeomans.Out-for-Delivery"

    /// The store that holds data this user owns (`.private` CloudKit scope, or a
    /// plain local store in the offline fallback). New objects are assigned here.
    private(set) var privateStore: NSPersistentStore?
    /// The store that holds data shared *with* this user as a participant
    /// (`.shared` CloudKit scope). nil for in-memory/preview and the offline
    /// fallback. The share-accept flow imports a shared record (baby or labor log)
    /// and its children into this store.
    private(set) var sharedStore: NSPersistentStore?
    /// True when the CloudKit-backed stores loaded (vs. the offline local fallback).
    private(set) var cloudKitEnabled = false

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(
            name: "OutForDelivery",
            managedObjectModel: Self.makeModel()
        )

        guard let privateDesc = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description")
        }

        if inMemory {
            privateDesc.url = URL(fileURLWithPath: "/dev/null")
            privateDesc.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDesc]
        } else {
            // History tracking + remote-change notifications let CloudKit merge
            // peer/device changes into the view context automatically. Both stores
            // need them.
            for key in [NSPersistentHistoryTrackingKey,
                        NSPersistentStoreRemoteChangeNotificationPostOptionKey] {
                privateDesc.setOption(true as NSNumber, forKey: key)
            }
            let privateOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID)
            privateOptions.databaseScope = .private
            privateDesc.cloudKitContainerOptions = privateOptions

            // Second store for data shared WITH this user. Same model + history
            // options, a distinct file, and the `.shared` database scope. The
            // container routes objects to the right store and presents both through
            // the one viewContext.
            let sharedDesc = privateDesc.copy() as! NSPersistentStoreDescription
            sharedDesc.url = privateDesc.url?
                .deletingLastPathComponent()
                .appendingPathComponent("shared.sqlite")
            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID)
            sharedOptions.databaseScope = .shared
            sharedDesc.cloudKitContainerOptions = sharedOptions

            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        }

        var loadError: Error?
        container.loadPersistentStores { [self] description, error in
            if let error {
                loadError = error
                return
            }
            // Match the loaded store back to its scope so callers (SharingManager,
            // the accept flow, store affinity) can address each store.
            switch description.cloudKitContainerOptions?.databaseScope {
            case .shared: sharedStore = store(for: description)
            default: privateStore = store(for: description)
            }
        }

        // Fall back to a local-only store if CloudKit setup fails (e.g. running
        // without an iCloud-enabled profile). The app still works fully offline;
        // only cross-device/-account sync is unavailable. Mirrors the old AppData
        // fallback.
        if loadError != nil, !inMemory {
            privateStore = nil
            sharedStore = nil
            privateDesc.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDesc]
            loadError = nil
            container.loadPersistentStores { [self] description, error in
                if let error { loadError = error; return }
                privateStore = store(for: description)
            }
        } else if loadError == nil, !inMemory {
            cloudKitEnabled = true
        }
        if let loadError {
            fatalError("Could not load persistent store: \(loadError)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Query generations pin the context to a snapshot of the on-disk store; they
        // are unsupported on an in-memory store and throw an (uncatchable) ObjC
        // exception there, so only pin the real store.
        if !inMemory {
            try? container.viewContext.setQueryGenerationFrom(.current)
        }

        let laborLog = ensureLaborLog()
        backfillRelationships(laborLog: laborLog)

        if !inMemory {
            Logger.sharing.info("Stack ready. cloudKit=\(self.cloudKitEnabled, privacy: .public) private=\(self.privateStore != nil, privacy: .public) shared=\(self.sharedStore != nil, privacy: .public) contractions=\(laborLog.contractions?.count ?? 0, privacy: .public) laborLogInSharedStore=\(laborLog.objectID.persistentStore === self.sharedStore, privacy: .public)")
        }

        #if DEBUG
        initializeCloudKitSchemaIfPossible()
        #endif
    }

    /// Resolves the loaded `NSPersistentStore` for a description via its URL.
    private func store(for description: NSPersistentStoreDescription) -> NSPersistentStore? {
        guard let url = description.url else { return nil }
        return container.persistentStoreCoordinator.persistentStore(for: url)
    }

    #if DEBUG
    /// Pushes the model to the CloudKit development schema so the new entities,
    /// fields, and the share record type exist server-side before any sync.
    ///
    /// `initializeCloudKitSchema` is a slow, network-blocking call, so it is NOT run
    /// on normal launches or under tests. Run it deliberately by adding the
    /// `-InitializeCloudKitSchema` launch argument to the scheme, on an iCloud-signed
    /// device, then verify the schema in the CloudKit Console.
    private func initializeCloudKitSchemaIfPossible() {
        guard cloudKitEnabled,
              ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") else { return }
        do {
            try container.initializeCloudKitSchema(options: [])
        } catch {
            // Non-fatal in development: the app still runs against the local mirror.
            print("initializeCloudKitSchema failed: \(error)")
        }
    }
    #endif

    // MARK: - LaborLog anchor

    /// The single LaborLog root for this user's contraction data. Created on first
    /// launch in the PRIVATE store; every contraction relates to it so the labor
    /// history shares as one CKShare. Babies are NOT anchored here — each Baby is its
    /// own share root.
    ///
    /// Multiplicity note: a participant who accepts a contraction-log share receives
    /// the owner's LaborLog in their SHARED store, and may also have an (empty) private
    /// one created here on a cold first launch. We therefore (a) never create a second
    /// LaborLog when ANY already exists, and (b) prefer the shared-store LaborLog in
    /// `laborLog` so participant-logged contractions attach to the shared graph and
    /// reach the owner.
    @discardableResult
    func ensureLaborLog() -> LaborLog {
        if let existing = preferredLaborLog() { return existing }
        let laborLog = LaborLog(context: viewContext)
        laborLog.id = UUID()
        laborLog.createdAt = Date()
        if let privateStore {
            viewContext.assign(laborLog, to: privateStore)
        }
        try? viewContext.save()
        return laborLog
    }

    /// Convenience accessor for the LaborLog new contractions attach to.
    var laborLog: LaborLog { ensureLaborLog() }

    /// Returns the LaborLog to use, preferring one that lives in the shared store
    /// (an accepted log) over a local private one. nil when none exist yet.
    private func preferredLaborLog() -> LaborLog? {
        let request = LaborLog.fetchRequest()
        // Deterministic order so the same log is chosen across launches even if an
        // earlier build left more than one (the contraction must attach to, and the
        // share must root at, the same log).
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let all = (try? viewContext.fetch(request)) ?? []
        if all.isEmpty { return nil }
        if let sharedStore,
           let shared = all.first(where: { $0.objectID.persistentStore === sharedStore }) {
            return shared
        }
        return all.first
    }

    /// Migrates existing on-device rows to the per-record relationships left behind by
    /// the previous single-Household-share design:
    /// - Feeds with `baby == nil` are matched to their Baby by `babyID`.
    /// - Contractions with `laborLog == nil` are attached to our own LaborLog (private
    ///   store only, so a participant's private history is never pulled into a share).
    /// - Babies need no anchor (each is its own share root). The old Household entity is
    ///   gone from the model, so its rows drop out via store migration — nothing to do.
    private func backfillRelationships(laborLog: LaborLog) {
        var changed = false

        // Feeds → baby.
        let feedRequest = Feed.fetchRequest()
        feedRequest.predicate = NSPredicate(format: "baby == nil")
        let orphanFeeds = (try? viewContext.fetch(feedRequest)) ?? []
        if !orphanFeeds.isEmpty {
            var babiesByID: [UUID: Baby] = [:]
            for baby in (try? viewContext.fetch(Baby.fetchRequest())) ?? [] {
                babiesByID[baby.id] = baby
            }
            for feed in orphanFeeds {
                if let baby = babiesByID[feed.babyID] {
                    feed.baby = baby
                    changed = true
                }
            }
        }

        // Contractions → our LaborLog (only one we own).
        if laborLog.objectID.persistentStore !== sharedStore {
            let contractionRequest = Contraction.fetchRequest()
            contractionRequest.predicate = NSPredicate(format: "laborLog == nil")
            for contraction in (try? viewContext.fetch(contractionRequest)) ?? [] {
                contraction.laborLog = laborLog
                changed = true
            }
        }

        if changed { try? viewContext.save() }
    }

    // MARK: - Programmatic model

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let laborLog = NSEntityDescription()
        laborLog.name = "LaborLog"
        laborLog.managedObjectClassName = "LaborLog"

        let contraction = NSEntityDescription()
        contraction.name = "Contraction"
        contraction.managedObjectClassName = "Contraction"

        let baby = NSEntityDescription()
        baby.name = "Baby"
        baby.managedObjectClassName = "Baby"

        let feed = NSEntityDescription()
        feed.name = "Feed"
        feed.managedObjectClassName = "Feed"

        let diaper = NSEntityDescription()
        diaper.name = "Diaper"
        diaper.managedObjectClassName = "Diaper"

        let pump = NSEntityDescription()
        pump.name = "Pump"
        pump.managedObjectClassName = "Pump"

        // CloudKit requires every attribute to be optional OR carry a default.
        // Non-optional Swift properties are backed by attributes with defaults so
        // a value is always present at read time.
        func attr(_ name: String,
                  _ type: NSAttributeType,
                  optional: Bool = true,
                  defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            if let defaultValue { a.defaultValue = defaultValue }
            return a
        }

        let epoch = Date(timeIntervalSince1970: 0)

        // LaborLog
        let llId = attr("id", .UUIDAttributeType)
        let llCreatedAt = attr("createdAt", .dateAttributeType)

        // Contraction
        let cId = attr("id", .UUIDAttributeType)
        let cStart = attr("startDate", .dateAttributeType, optional: false, defaultValue: epoch)
        let cEnd = attr("endDate", .dateAttributeType)
        let cNewSession = attr("startsNewSession", .booleanAttributeType, optional: false, defaultValue: false)
        let cLoggedByID = attr("loggedByID", .stringAttributeType)
        let cLoggedByName = attr("loggedByName", .stringAttributeType)

        // Baby
        let bId = attr("id", .UUIDAttributeType)
        let bName = attr("name", .stringAttributeType, optional: false, defaultValue: "")
        let bBirth = attr("birthDate", .dateAttributeType, optional: false, defaultValue: epoch)
        let bArchived = attr("isArchived", .booleanAttributeType, optional: false, defaultValue: false)
        let bCreated = attr("createdAt", .dateAttributeType, optional: false, defaultValue: epoch)
        let bReminderOn = attr("feedReminderEnabled", .booleanAttributeType, optional: false, defaultValue: false)
        let bInterval = attr("feedReminderInterval", .doubleAttributeType, optional: false, defaultValue: 3.0 * 60 * 60)
        let bAlarmID = attr("feedAlarmID", .UUIDAttributeType)

        // Feed
        let fId = attr("id", .UUIDAttributeType)
        let fBabyID = attr("babyID", .UUIDAttributeType)
        let fTimestamp = attr("timestamp", .dateAttributeType, optional: false, defaultValue: epoch)
        let fKind = attr("kind", .stringAttributeType, optional: false, defaultValue: "unspecified")
        let fVolume = attr("volumeNumber", .doubleAttributeType)
        let fLeft = attr("leftMinutesNumber", .integer64AttributeType)
        let fRight = attr("rightMinutesNumber", .integer64AttributeType)
        let fNote = attr("note", .stringAttributeType)
        let fBottleContent = attr("bottleContentRaw", .stringAttributeType)
        let fLoggedByID = attr("loggedByID", .stringAttributeType)
        let fLoggedByName = attr("loggedByName", .stringAttributeType)

        // Diaper
        let dId = attr("id", .UUIDAttributeType)
        let dBabyID = attr("babyID", .UUIDAttributeType)
        let dTimestamp = attr("timestamp", .dateAttributeType, optional: false, defaultValue: epoch)
        let dKind = attr("kind", .stringAttributeType, optional: false, defaultValue: "wet")
        let dColor = attr("color", .stringAttributeType)
        let dConsistency = attr("consistency", .stringAttributeType)
        let dNote = attr("note", .stringAttributeType)
        let dLoggedByID = attr("loggedByID", .stringAttributeType)
        let dLoggedByName = attr("loggedByName", .stringAttributeType)

        // Pump
        let pId = attr("id", .UUIDAttributeType)
        let pBabyID = attr("babyID", .UUIDAttributeType)
        let pTimestamp = attr("timestamp", .dateAttributeType, optional: false, defaultValue: epoch)
        let pLeft = attr("leftVolumeNumber", .doubleAttributeType)
        let pRight = attr("rightVolumeNumber", .doubleAttributeType)
        let pCombined = attr("combinedVolumeNumber", .doubleAttributeType)
        let pDuration = attr("durationNumber", .doubleAttributeType)
        let pNote = attr("note", .stringAttributeType)
        let pLoggedByID = attr("loggedByID", .stringAttributeType)
        let pLoggedByName = attr("loggedByName", .stringAttributeType)

        // Relationships (every relationship optional, with an inverse — CloudKit rules).
        func toMany(_ name: String, _ dest: NSEntityDescription) -> NSRelationshipDescription {
            let r = NSRelationshipDescription()
            r.name = name
            r.destinationEntity = dest
            r.minCount = 0
            r.maxCount = 0
            r.deleteRule = .cascadeDeleteRule
            r.isOptional = true
            return r
        }
        func toOne(_ name: String, _ dest: NSEntityDescription) -> NSRelationshipDescription {
            let r = NSRelationshipDescription()
            r.name = name
            r.destinationEntity = dest
            r.minCount = 0
            r.maxCount = 1
            r.deleteRule = .nullifyDeleteRule
            r.isOptional = true
            return r
        }

        // LaborLog 1—* Contraction (cascade from the share root).
        let llContractions = toMany("contractions", contraction)
        let cLaborLog = toOne("laborLog", laborLog)
        llContractions.inverseRelationship = cLaborLog
        cLaborLog.inverseRelationship = llContractions

        // Baby 1—* Feed (feeds travel with the baby's share; cascade from the root).
        let bFeeds = toMany("feeds", feed)
        let fBaby = toOne("baby", baby)
        bFeeds.inverseRelationship = fBaby
        fBaby.inverseRelationship = bFeeds

        // Baby 1—* Diaper (cascade from the share root, like feeds).
        let bDiapers = toMany("diapers", diaper)
        let dBaby = toOne("baby", baby)
        bDiapers.inverseRelationship = dBaby
        dBaby.inverseRelationship = bDiapers

        // Baby 1—* Pump (cascade from the share root, like feeds).
        let bPumps = toMany("pumps", pump)
        let pBaby = toOne("baby", baby)
        bPumps.inverseRelationship = pBaby
        pBaby.inverseRelationship = bPumps

        laborLog.properties = [llId, llCreatedAt, llContractions]
        contraction.properties = [cId, cStart, cEnd, cNewSession, cLoggedByID, cLoggedByName, cLaborLog]
        baby.properties = [bId, bName, bBirth, bArchived, bCreated, bReminderOn, bInterval, bAlarmID, bFeeds, bDiapers, bPumps]
        feed.properties = [fId, fBabyID, fTimestamp, fKind, fVolume, fLeft, fRight, fNote, fBottleContent, fLoggedByID, fLoggedByName, fBaby]
        diaper.properties = [dId, dBabyID, dTimestamp, dKind, dColor, dConsistency, dNote, dLoggedByID, dLoggedByName, dBaby]
        pump.properties = [pId, pBabyID, pTimestamp, pLeft, pRight, pCombined, pDuration, pNote, pLoggedByID, pLoggedByName, pBaby]

        model.entities = [laborLog, contraction, baby, feed, diaper, pump]
        return model
    }
}
