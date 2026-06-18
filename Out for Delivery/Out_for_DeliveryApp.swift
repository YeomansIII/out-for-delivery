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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppData.shared.container)
    }
}
