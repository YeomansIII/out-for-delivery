//
//  AppMode.swift
//  Out for Delivery
//
//  App-wide mode + active-baby state. The app presents one of two modes:
//  labor (contraction timer) or newborn (baby tracking). Creating the first
//  baby profile switches to newborn mode; thereafter the user can toggle freely.
//

import Foundation
import Observation

enum AppMode: String {
    case labor
    case newborn
}

@MainActor
@Observable
final class AppState {
    /// Shared instance. Referenced directly by views (mirroring `ContractionService.shared`
    /// and `AppData.shared`) rather than injected via the environment — SwiftUI sheets do
    /// not reliably inherit a custom `@Observable` placed in the environment.
    static let shared = AppState()

    /// Which baby-related sheet, if any, is presented at the top level.
    enum Sheet: Identifiable {
        case addBaby
        case manageBabies
        case family
        var id: Self { self }
    }

    /// The user-selected mode. Only meaningful once at least one baby profile exists;
    /// with no babies the app always presents labor mode (enforced in `RootView`).
    var mode: AppMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }

    /// The active baby, whose data newborn mode displays. `nil` falls back to the first baby.
    var activeBabyID: UUID? {
        didSet { defaults.set(activeBabyID?.uuidString, forKey: Keys.activeBaby) }
    }

    /// Top-level baby sheet presentation (not persisted).
    var sheet: Sheet?

    /// Preferred unit for entering and displaying bottle volumes (app-wide).
    var volumeUnit: VolumeUnit {
        didSet { defaults.set(volumeUnit.rawValue, forKey: Keys.volumeUnit) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let mode = "appMode"
        static let activeBaby = "activeBabyID"
        static let volumeUnit = "volumeUnit"
    }

    private init() {
        mode = AppMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .labor
        if let raw = defaults.string(forKey: Keys.activeBaby) {
            activeBabyID = UUID(uuidString: raw)
        }
        volumeUnit = VolumeUnit(rawValue: defaults.string(forKey: Keys.volumeUnit) ?? "") ?? .milliliters
    }

    /// Called when a new baby profile is created: make it active and flip to newborn mode.
    func onBabyCreated(_ baby: Baby) {
        activeBabyID = baby.id
        mode = .newborn
    }
}
