//
//  FeedReminderAlarmWidget.swift
//  LiveActivity
//
//  Renders the feed-on-demand reminder's non-alerting presentations (Lock Screen,
//  Dynamic Island, StandBy) while the AlarmKit countdown runs. AlarmKit requires a
//  widget extension when an app uses a countdown presentation, otherwise the system
//  may dismiss alarms without alerting. The alerting (full-screen) UI itself is
//  system-templated from the alarm's AlarmPresentation.
//

import AlarmKit
import WidgetKit
import SwiftUI

struct FeedReminderAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FeedReminderMetadata>.self) { context in
            // Lock Screen / banner
            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                content(state: context.state, attributes: context.attributes)
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.2))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "drop.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    content(state: context.state, attributes: context.attributes)
                }
            } compactLeading: {
                Image(systemName: "drop.fill")
                    .symbolRenderingMode(.hierarchical)
            } compactTrailing: {
                compactCountdown(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: "drop.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .keylineTint(.accentColor)
        }
    }

    @ViewBuilder
    private func content(
        state: AlarmPresentationState,
        attributes: AlarmAttributes<FeedReminderMetadata>
    ) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            VStack(alignment: .leading, spacing: 2) {
                if let title = attributes.presentation.countdown?.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(timerInterval: Date()...countdown.fireDate, countsDown: true)
                    .font(.system(.headline, design: .rounded).monospacedDigit())
            }
        case .paused:
            Text(attributes.presentation.paused?.title ?? "Paused")
                .font(.headline)
        case .alert:
            Text(attributes.presentation.alert.title)
                .font(.headline)
        @unknown default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func compactCountdown(state: AlarmPresentationState) -> some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: Date()...countdown.fireDate, countsDown: true)
        } else {
            Image(systemName: "drop.fill")
        }
    }
}
