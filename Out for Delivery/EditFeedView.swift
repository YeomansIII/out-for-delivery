//
//  EditFeedView.swift
//  Out for Delivery
//
//  Bottom-sheet editor for a feed: its time, kind, and per-kind detail (bottle
//  volume, or breast minutes per side). Works in two modes:
//
//  - **Create** (`init(creating:)`): edits an in-memory draft and reports it on
//    Save. The feed is only inserted by the caller on confirm, so logging never
//    races the sheet presentation (no insert-driven `@Query` / CloudKit churn
//    while the sheet is appearing).
//  - **Edit** (`init(editing:)`): pre-filled from an existing feed.
//
//  Newborn events are routinely backfilled and corrected, so editing is first-class.
//

import SwiftUI

struct EditFeedView: View {
    /// The values the editor collects; the caller decides whether to insert or update.
    struct Draft {
        var timestamp: Date
        var kind: FeedKind
        var volume: Double?        // canonical milliliters
        var leftMinutes: Int?
        var rightMinutes: Int?
    }

    private let navTitle: String
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss

    private let unit = AppState.shared.volumeUnit

    @State private var timestamp: Date
    @State private var kind: FeedKind
    @State private var volumeText: String
    @State private var leftMinutesText: String
    @State private var rightMinutesText: String

    /// Create a new feed of `kind`, defaulting to now.
    init(creating kind: FeedKind, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Log \(kind.label)"
        self.onSave = onSave
        _timestamp = State(initialValue: Date())
        _kind = State(initialValue: kind)
        _volumeText = State(initialValue: "")
        _leftMinutesText = State(initialValue: "")
        _rightMinutesText = State(initialValue: "")
    }

    /// Edit an existing feed.
    init(editing feed: Feed, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Edit Feed"
        self.onSave = onSave
        _timestamp = State(initialValue: feed.timestamp)
        _kind = State(initialValue: feed.feedKind)
        if let ml = feed.volume {
            _volumeText = State(initialValue: AppState.shared.volumeUnit.inputString(fromMilliliters: ml))
        } else {
            _volumeText = State(initialValue: "")
        }
        _leftMinutesText = State(initialValue: feed.leftMinutes.map(String.init) ?? "")
        _rightMinutesText = State(initialValue: feed.rightMinutes.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Feed time") {
                    DatePicker(
                        "Fed at",
                        selection: $timestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(FeedKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .bottle {
                    Section("Amount") {
                        HStack {
                            TextField("Amount", text: $volumeText)
                                .keyboardType(.decimalPad)
                            Text(unit.abbreviation)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if kind == .breast {
                    Section("Time on each side") {
                        minutesRow("Left", text: $leftMinutesText)
                        minutesRow("Right", text: $rightMinutesText)
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Draft(
                            timestamp: timestamp,
                            kind: kind,
                            volume: volumeMilliliters(),
                            leftMinutes: minutes(leftMinutesText),
                            rightMinutes: minutes(rightMinutesText)
                        ))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func minutesRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 60)
            Text("min")
                .foregroundStyle(.secondary)
        }
    }

    /// The entered amount converted to canonical milliliters, or nil when the feed
    /// isn't a bottle or no valid positive amount was entered.
    private func volumeMilliliters() -> Double? {
        guard kind == .bottle else { return nil }
        let normalized = volumeText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return unit.toMilliliters(value)
    }

    /// Parses a side's minutes, or nil when not a breast feed / no positive value.
    private func minutes(_ text: String) -> Int? {
        guard kind == .breast, let value = Int(text), value > 0 else { return nil }
        return value
    }
}
