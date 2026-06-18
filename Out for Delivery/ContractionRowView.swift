//
//  ContractionRowView.swift
//  Out for Delivery
//

import SwiftUI

struct ContractionRowView: View {
    let contraction: Contraction
    let number: Int
    let interval: TimeInterval?
    let canToggleSessionStart: Bool
    let isManualSessionStart: Bool
    let onToggleSessionStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("#\(number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(TimeFormatting.clock(contraction.startDate))
                    .font(.body)
                Text(contraction.isInProgress ? "in progress" : "lasted \(durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(durationText)
                    .font(.body.monospacedDigit())
                Text(intervalText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to edit")
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if canToggleSessionStart {
                Button {
                    onToggleSessionStart()
                } label: {
                    if isManualSessionStart {
                        Label("Unmark", systemImage: "arrow.uturn.backward")
                    } else {
                        Label("New session", systemImage: "calendar.badge.plus")
                    }
                }
                .tint(isManualSessionStart ? .gray : .accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var durationText: String {
        if let d = contraction.duration {
            return TimeFormatting.mmss(d)
        }
        return "—"
    }

    private var intervalText: String {
        guard let i = interval else { return "—" }
        return TimeFormatting.mmss(i)
    }

    private var accessibilityLabel: String {
        var parts = ["Contraction \(number)"]
        parts.append("started at \(TimeFormatting.clock(contraction.startDate))")
        if contraction.isInProgress {
            parts.append("in progress")
        } else if let d = contraction.duration {
            parts.append("lasted \(TimeFormatting.mmss(d))")
        }
        if let i = interval {
            parts.append("\(TimeFormatting.mmss(i)) since the previous one")
        }
        return parts.joined(separator: ", ")
    }
}
