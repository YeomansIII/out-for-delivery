//
//  Out_for_DeliveryApp.swift
//  Out for Delivery
//

import SwiftUI
import SwiftData

@main
struct Out_for_DeliveryApp: App {
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppData.shared.container)
    }
}
