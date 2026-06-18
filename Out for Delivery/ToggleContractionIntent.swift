//
//  ToggleContractionIntent.swift
//  Out for Delivery
//
//  Shared between the app target and the widget extension target.
//
//  TARGET MEMBERSHIP: must be checked for BOTH the app target and the
//  LiveActivity widget target (File Inspector → Target Membership).
//
//  `LiveActivityIntent.perform()` runs in the app's process, so the actual
//  toggle is invoked through `IntentDispatcher.toggle`, which the app
//  registers at launch. This keeps `ContractionService` and its
//  dependencies out of the widget target.
//

import Foundation
import AppIntents

public enum IntentDispatcher {
    /// Registered by the app at launch. The widget extension also links this
    /// file but never invokes the closure — the system routes the intent to
    /// the app process for execution.
    @MainActor public static var toggle: @MainActor () -> Void = {}
}

public struct ToggleContractionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Toggle Contraction"
    public static var description = IntentDescription(
        "Start a new contraction when resting, or stop the in-progress one."
    )

    /// Allow the toggle to run straight from the Lock Screen without unlocking
    /// the device. This is the framework default, but we pin it explicitly so
    /// the Live Activity button stays interactive on the surfaces that honor it
    /// (Dynamic Island, StandBy, Home Screen). NOTE: iOS does not honor this for
    /// the Lock Screen card on non-media intents — that surface always requires
    /// device authentication for a `LiveActivityIntent`. See the discussion in
    /// the project notes.
    public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentDispatcher.toggle()
        return .result()
    }
}
