//
//  ContractionLiveActivity.swift
//  OutForDeliveryWidgets
//
//  Live Activity widget — Lock Screen + Dynamic Island presentations.
//
//  TARGET MEMBERSHIP:
//  - This file belongs to the widget extension target ONLY.
//  - `ContractionActivityAttributes.swift` and `ToggleContractionIntent.swift`
//    (from the app target) must be added to the widget extension target's
//    membership as well (check the target membership checkbox in the File
//    Inspector for both files).
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ContractionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ContractionActivityAttributes.self) { context in
            // Lock Screen / banner UI
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.black.opacity(0.2))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Image(systemName: glyph(for: context.state))
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                        Text(themedLine(for: context.state))
                            .font(.caption.weight(.medium))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PrimaryCounter(state: context.state)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {}
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        SecondaryStats(state: context.state)
                        Spacer()
                        ToggleButton(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: glyph(for: context.state))
                    .symbolRenderingMode(.hierarchical)
            } compactTrailing: {
                PrimaryCounter(state: context.state)
                    .monospacedDigit()
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
                Text("\(state.count) updates")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
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

// MARK: - Primary counter (self-updating)

private struct PrimaryCounter: View {
    let state: ContractionActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .contracting:
            if let start = state.currentStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text("0:00")
            }
        case .resting:
            if let last = state.lastStart {
                Text(timerInterval: last...Date.distantFuture, countsDown: false)
            } else {
                Text("—")
            }
        }
    }
}

// MARK: - Secondary stats

private struct SecondaryStats: View {
    let state: ContractionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if let d = state.lastDuration {
                Text("last lasted \(mmss(d))")
            }
            if let i = state.lastInterval {
                Text("· last interval \(mmss(i))")
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

    var body: some View {
        Button(intent: ToggleContractionIntent()) {
            Text(state.phase == .contracting ? "Stop" : "Start")
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 70)
        }
        .tint(state.phase == .contracting ? .red : .accentColor)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}
