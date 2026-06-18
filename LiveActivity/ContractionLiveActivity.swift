//
//  ContractionLiveActivity.swift
//  LiveActivity
//
//  Lock Screen + Dynamic Island presentations.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct ContractionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ContractionActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.black.opacity(0.2))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(themedLine(for: context.state))
                            .font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: glyph(for: context.state))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .font(.caption)
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.state.patternMet {
                            Text("5-1-1")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.25), in: Capsule())
                        } else if context.state.sessionCount > 0 {
                            Text("\(context.state.sessionCount) logged")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            PrimaryCounter(state: context.state)
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            SecondaryStats(state: context.state)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ToggleButton(state: context.state, diameter: 52)
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: glyph(for: context.state))
                    .symbolRenderingMode(.hierarchical)
            } compactTrailing: {
                // Cap the width so `Text(timerInterval:)` doesn't reserve extra
                // layout space and stretch the compact pill across the notch.
                PrimaryCounter(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: glyph(for: context.state))
            }
            .keylineTint(.accentColor)
        }
    }

    private func glyph(for state: ContractionActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .contracting: return "shippingbox.and.arrow.backward.fill"
        case .resting: return state.patternMet ? "checkmark.seal.fill" : "shippingbox.fill"
        }
    }

    private func themedLine(for state: ContractionActivityAttributes.ContentState) -> String {
        if state.count == 0 { return "Order placed" }
        if state.patternMet { return "Arriving soon" }
        switch state.phase {
        case .contracting: return "Out for delivery"
        case .resting: return "In transit"
        }
    }
}

// MARK: - Lock Screen card

private struct LockScreenView: View {
    let state: ContractionActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .symbolRenderingMode(.hierarchical)
                Text(themedLine)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(state.sessionCount) updates")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center) {
                PrimaryCounter(state: state)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                ToggleButton(state: state)
            }

            SecondaryStats(state: state)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding()
        .opacity(isStale ? 0.6 : 1.0)
    }

    private var glyph: String {
        switch state.phase {
        case .contracting: return "shippingbox.and.arrow.backward.fill"
        case .resting: return state.patternMet ? "checkmark.seal.fill" : "shippingbox.fill"
        }
    }

    private var themedLine: String {
        if state.count == 0 { return "Order placed" }
        if state.patternMet { return "Arriving soon" }
        switch state.phase {
        case .contracting: return "Out for delivery"
        case .resting: return "In transit"
        }
    }
}

// MARK: - Primary self-updating counter

private struct PrimaryCounter: View {
    let state: ContractionActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .contracting:
            if let start = state.currentStart {
                Text(timerInterval: countUpRange(from: start), countsDown: false)
            } else {
                Text("0:00")
            }
        case .resting:
            if let last = state.lastStart {
                Text(timerInterval: countUpRange(from: last), countsDown: false)
            } else {
                Text("—")
            }
        }
    }

    /// Bound the count-up range to just under an hour so `Text(timerInterval:)`
    /// reserves only `mm:ss` of width. Passing `.distantFuture` makes the label
    /// reserve space for an `h:mm:ss` value, which blows out the Dynamic Island
    /// and Lock Screen layouts.
    private func countUpRange(from start: Date) -> ClosedRange<Date> {
        start...start.addingTimeInterval(59 * 60 + 59)
    }
}

// MARK: - Secondary stats

private struct SecondaryStats: View {
    let state: ContractionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if let d = state.avgDuration {
                Text("avg length \(mmss(d))")
            }
            if let i = state.avgInterval {
                Text("· avg interval \(mmss(i))")
            }
            if state.patternMet {
                Text("· 5-1-1 met")
            }
        }
    }

    private func mmss(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Toggle button

private struct ToggleButton: View {
    let state: ContractionActivityAttributes.ContentState
    var diameter: CGFloat = 60

    private var isContracting: Bool { state.phase == .contracting }

    var body: some View {
        Button(intent: ToggleContractionIntent()) {
            Image(systemName: isContracting ? "stop.fill" : "play.fill")
                .font(.system(size: diameter * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(isContracting ? Color.red : Color.accentColor, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isContracting ? "Stop contraction" : "Start contraction")
    }
}
