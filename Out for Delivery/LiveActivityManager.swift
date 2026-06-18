//
//  LiveActivityManager.swift
//  Out for Delivery
//
//  Owns the Live Activity lifecycle. Starts/updates/ends a single activity for
//  the current session. Re-requests a fresh activity when the app comes to
//  foreground to reset the 8-hour system cap if the existing one is near
//  expiry or missing.
//

import Foundation
import ActivityKit

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    private var currentActivity: Activity<ContractionActivityAttributes>? {
        Activity<ContractionActivityAttributes>.activities.first
    }

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// True when there's an active session (any logged contractions) but no live activity.
    func needsRestart(snapshot: ContractionService.Snapshot) -> Bool {
        snapshot.count > 0 && currentActivity == nil
    }

    /// Start a new Live Activity. Must be called while the app is foreground.
    func startOrUpdate(with snapshot: ContractionService.Snapshot) async {
        if let existing = currentActivity {
            await existing.update(content(for: snapshot))
            return
        }
        guard areActivitiesEnabled else { return }
        let attributes = ContractionActivityAttributes()
        do {
            _ = try Activity<ContractionActivityAttributes>.request(
                attributes: attributes,
                content: content(for: snapshot),
                pushType: nil
            )
        } catch {
            // No-op: the activity may be disabled by the user or rejected by the system.
        }
    }

    func update(with snapshot: ContractionService.Snapshot) async {
        guard let activity = currentActivity else { return }
        await activity.update(content(for: snapshot))
    }

    func end() async {
        for activity in Activity<ContractionActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Called when the user explicitly toggles "Hide from Lock Screen".
    func hide() async {
        await end()
    }

    private func content(for snapshot: ContractionService.Snapshot) -> ActivityContent<ContractionActivityAttributes.ContentState> {
        let state = ContractionActivityAttributes.ContentState(
            phase: snapshot.phase,
            currentStart: snapshot.currentStart,
            lastStart: snapshot.lastStart,
            lastDuration: snapshot.lastDuration,
            lastInterval: snapshot.lastInterval,
            count: snapshot.count,
            sessionCount: snapshot.sessionCount,
            avgInterval: snapshot.avgInterval,
            avgDuration: snapshot.avgDuration,
            patternMet: snapshot.patternMet
        )
        // staleDate: about 30 minutes past the last meaningful anchor so the
        // system can dim stale data if the activity isn't being driven.
        let anchor = snapshot.currentStart ?? snapshot.lastStart ?? Date()
        let staleDate = anchor.addingTimeInterval(30 * 60)
        return ActivityContent(state: state, staleDate: staleDate)
    }
}
