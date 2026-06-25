//
//  ToggleContractionIntent.swift
//  Out for Delivery
//
//  Cross-target shared types: this file is a member of BOTH the app target and
//  the LiveActivity widget extension target (File Inspector → Target Membership).
//  It holds the intents/metadata both targets need so the widget can render app
//  controls and AlarmKit presentations without pulling in the app's services.
//
//  `LiveActivityIntent.perform()` runs in the app's process, so the actual work
//  is invoked through a dispatcher closure the app registers at launch. This keeps
//  `ContractionService` / `FeedService` and their dependencies out of the widget
//  target.
//

import Foundation
import AppIntents
import AlarmKit

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

// MARK: - Feed-on-demand reminder (newborn mode)

/// Metadata attached to a feed-reminder alarm. The visible content comes from the
/// alarm's `AlarmPresentation`, so this stays empty — but AlarmKit requires a
/// concrete `AlarmMetadata` type, and sharing it lets the widget specialize
/// `AlarmAttributes<FeedReminderMetadata>`.
public struct FeedReminderMetadata: AlarmMetadata {
    public init() {}
}

public enum FeedReminderDispatcher {
    /// Registered by the app at launch. Invoked (in the app's process) when a feed
    /// reminder is stopped from its alert, with the Baby's id string, so the app can
    /// clear the stored alarm id. The widget links this file but never invokes the
    /// closure — the system routes the intent to the app process for execution.
    @MainActor public static var stop: @MainActor (String) -> Void = { _ in }
}

/// Runs when a person taps Stop on a firing feed reminder. AlarmKit stops the alarm
/// itself; this intent additionally clears the app's per-baby alarm bookkeeping.
public struct StopFeedReminderIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Stop Feed Reminder"

    @Parameter(title: "Baby ID")
    public var babyID: String

    public init() {}
    public init(babyID: String) { self.babyID = babyID }

    @MainActor
    public func perform() async throws -> some IntentResult {
        FeedReminderDispatcher.stop(babyID)
        return .result()
    }
}
