//
//  AppData.swift
//  Out for Delivery
//
//  Single shared CloudKit-backed SwiftData stack. Used by the app's
//  `.modelContainer(...)` and by `ToggleContractionIntent.perform()` running
//  in-process from the Live Activity.
//

import Foundation
import SwiftData

@MainActor
final class AppData {
    static let shared = AppData()

    let container: ModelContainer

    private init() {
        let schema = Schema([Contraction.self, Baby.self, Feed.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            self.container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Fall back to a local-only store if CloudKit discovery fails (e.g. running
            // without an iCloud-enabled profile). The app still works fully offline;
            // only cross-device sync is unavailable.
            let localOnly = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                self.container = try ModelContainer(for: schema, configurations: [localOnly])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }
}
