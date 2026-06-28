//
//  Out_for_DeliveryApp.swift
//  Out for Delivery
//

import SwiftUI
import CoreData

@main
struct Out_for_DeliveryApp: App {
    // SwiftUI apps need an application delegate to accept CloudKit share
    // invitations; it points new scenes at our SceneDelegate (see AppDelegate).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Register the toggle handler that `ToggleContractionIntent.perform()`
        // calls. The intent runs in this (the app's) process, so the closure
        // captures the app's ContractionService singleton.
        IntentDispatcher.toggle = {
            ContractionService.shared.toggle()
        }

        // Register the in-process handler for the feed reminder's Stop intent so
        // the per-baby alarm bookkeeping stays in sync when a reminder is dismissed.
        // Alarm authorization is requested lazily, the first time a caregiver
        // enables a reminder (see FeedReminderManager.reschedule).
        FeedReminderManager.shared.registerIntentHandlers()

        // Resolve the current iCloud identity once so contractions and feeds can be
        // stamped with "who logged it" (attribution is informational, never required).
        Task { await CurrentUserIdentity.shared.warmUp() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext,
                             PersistenceController.shared.viewContext)
        }
    }
}
