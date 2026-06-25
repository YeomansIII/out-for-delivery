//
//  FeedReminderManager.swift
//  Out for Delivery
//
//  Owns the feed-on-demand reminder via AlarmKit. Each logged feed re-arms a
//  countdown to (last feed + interval); if it lapses with no new feed, AlarmKit
//  fires an alarm-style alert that overrides silent mode and Focus — like the
//  Clock app — so a sleeping caregiver doesn't miss a feed.
//
//  This is a deliberate, opt-in, per-baby exception to the app's otherwise calm,
//  no-alarm ethos (which still holds for labor mode / the contraction readout).
//

import Foundation
import AlarmKit
import ActivityKit
import SwiftUI

@MainActor
final class FeedReminderManager {
    static let shared = FeedReminderManager()
    private init() {}

    private var manager: AlarmManager { AlarmManager.shared }

    /// How long "Snooze" pushes the reminder out when tapped on the firing alarm.
    private let snoozeSeconds: TimeInterval = 15 * 60

    /// Registers the in-process handler for the Stop intent surfaced on the alarm.
    /// Call once at app launch (mirrors `IntentDispatcher.toggle`).
    func registerIntentHandlers() {
        FeedReminderDispatcher.stop = { babyIDString in
            guard let babyID = UUID(uuidString: babyIDString),
                  let baby = FeedService.shared.baby(with: babyID) else { return }
            baby.feedAlarmID = nil
            FeedService.shared.save()
        }
    }

    /// Requests alarm authorization if it hasn't been determined yet.
    /// Returns true when the app may schedule alarms.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
    }

    /// Cancels any armed reminder for this baby and, if the reminder is enabled,
    /// schedules a fresh countdown to (last feed + interval). Safe to call after
    /// every feed mutation and whenever the baby's reminder settings change.
    func reschedule(for baby: Baby) async {
        // Always clear the previous alarm first so we never stack reminders.
        if let existing = baby.feedAlarmID {
            try? manager.cancel(id: existing)
            baby.feedAlarmID = nil
        }

        guard baby.feedReminderEnabled else {
            FeedService.shared.save()
            return
        }

        guard await requestAuthorizationIfNeeded() else {
            // Permission unavailable — leave the alarm unset. We deliberately don't
            // flip the user's toggle; the UI surfaces the denied state separately.
            FeedService.shared.save()
            return
        }

        let last = FeedService.shared.lastFeed(for: baby.id)?.timestamp
        let remaining = FeedMath.remainingUntilFire(lastFeed: last, interval: baby.feedReminderInterval)

        let id = UUID()
        do {
            _ = try await manager.schedule(id: id, configuration: configuration(for: baby, preAlert: remaining))
            baby.feedAlarmID = id
        } catch {
            baby.feedAlarmID = nil
        }
        FeedService.shared.save()
    }

    /// Cancels the baby's reminder outright (e.g. the toggle is turned off).
    func cancel(for baby: Baby) {
        if let existing = baby.feedAlarmID {
            try? manager.cancel(id: existing)
            baby.feedAlarmID = nil
            FeedService.shared.save()
        }
    }

    // MARK: - Configuration

    private func configuration(for baby: Baby, preAlert: TimeInterval) -> AlarmManager.AlarmConfiguration<FeedReminderMetadata> {
        let name = baby.name.isEmpty ? "your baby" : baby.name

        // The system always provides the Stop button; we add a Snooze (repeat) that
        // pushes the countdown out by `snoozeSeconds`.
        let alert = AlarmPresentation.Alert(
            title: "Time to feed \(name)",
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown
        )
        let countdown = AlarmPresentation.Countdown(
            title: "Next feed for \(name)",
            pauseButton: AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.fill")
        )
        let paused = AlarmPresentation.Paused(
            title: "Paused",
            resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill")
        )
        let presentation = AlarmPresentation(alert: alert, countdown: countdown, paused: paused)

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: FeedReminderMetadata(),
            tintColor: Color.accentColor
        )

        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: preAlert, postAlert: snoozeSeconds),
            schedule: nil,
            attributes: attributes,
            stopIntent: StopFeedReminderIntent(babyID: baby.id.uuidString),
            secondaryIntent: nil,
            sound: .default
        )
    }
}
