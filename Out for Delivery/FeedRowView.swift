//
//  FeedRowView.swift
//  Out for Delivery
//
//  One logged feed in the recent-feeds list. Tap to edit the time, swipe to delete.
//

import SwiftUI

struct FeedRowView: View {
    let feed: Feed
    let number: Int
    /// Start-to-start interval since the previous feed, if any.
    let interval: TimeInterval?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("#\(number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(TimeFormatting.clock(feed.timestamp))
                    .font(.body)
                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(feed.timestamp, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let interval {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TimeFormatting.compact(interval))
                        .font(.body.monospacedDigit())
                    Text("since previous")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to edit")
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// "Bottle · 90 ml", "Breast · L 10m R 8m", etc. nil for a plain unspecified
    /// feed with no amount.
    private var detailText: String? {
        switch feed.feedKind {
        case .bottle:
            guard let ml = feed.volume else { return "Bottle" }
            return "Bottle · \(AppState.shared.volumeUnit.formatted(fromMilliliters: ml))"
        case .breast:
            var sides: [String] = []
            if let left = feed.leftMinutes, left > 0 { sides.append("L \(left)m") }
            if let right = feed.rightMinutes, right > 0 { sides.append("R \(right)m") }
            return sides.isEmpty ? "Breast" : "Breast · " + sides.joined(separator: " ")
        case .unspecified:
            return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Feed \(number)", "at \(TimeFormatting.clock(feed.timestamp))"]
        if let detailText {
            parts.append(detailText)
        }
        if let interval {
            parts.append("\(TimeFormatting.compact(interval)) since the previous one")
        }
        return parts.joined(separator: ", ")
    }
}
