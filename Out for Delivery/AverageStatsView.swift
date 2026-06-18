//
//  AverageStatsView.swift
//  Out for Delivery
//
//  Prominent, glanceable display of the two key labor metrics: average
//  start-to-start interval and average contraction length for the current
//  session.
//

import SwiftUI

struct AverageStatsView: View {
    let snapshot: ContractionService.Snapshot

    var body: some View {
        HStack(spacing: 12) {
            metric(
                title: "Avg interval",
                icon: "arrow.left.and.right",
                value: snapshot.avgInterval
            )
            metric(
                title: "Avg length",
                icon: "clock",
                value: snapshot.avgDuration
            )
        }
    }

    private func metric(title: String, icon: String, value: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value.map(TimeFormatting.mmss) ?? "—")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
