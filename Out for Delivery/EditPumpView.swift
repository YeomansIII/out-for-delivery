//
//  EditPumpView.swift
//  Out for Delivery
//
//  Bottom-sheet editor for a pump session (Epic 9): volume expressed — per side
//  (left / right) or as one combined total — plus an optional duration and note.
//  Volumes are entered/displayed in the app-wide preferred unit (ml or oz) and
//  stored canonically as milliliters, matching bottle feeds. Live timing is
//  deferred (mirrors the deferred nursing timer); duration is entered in minutes.
//
//  Create / Edit follow the same draft pattern as EditFeedView: the caller inserts
//  the session only on confirm, so logging never races the sheet presentation.
//

import SwiftUI

struct EditPumpView: View {
    /// How the volume is being entered.
    enum EntryMode: Hashable {
        case perSide
        case combined
    }

    /// The values the editor collects; the caller decides whether to insert or update.
    struct Draft {
        var timestamp: Date
        var leftVolume: Double?     // canonical milliliters
        var rightVolume: Double?    // canonical milliliters
        var combinedVolume: Double? // canonical milliliters
        var duration: TimeInterval?
        var note: String?
    }

    private let navTitle: String
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss

    private let unit = AppState.shared.volumeUnit

    @State private var timestamp: Date
    @State private var entryMode: EntryMode
    @State private var leftText: String
    @State private var rightText: String
    @State private var combinedText: String
    @State private var durationText: String
    @State private var note: String

    /// Create a new session, defaulting to per-side entry at now.
    init(creating: Void = (), onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Log Pump"
        self.onSave = onSave
        _timestamp = State(initialValue: Date())
        _entryMode = State(initialValue: .perSide)
        _leftText = State(initialValue: "")
        _rightText = State(initialValue: "")
        _combinedText = State(initialValue: "")
        _durationText = State(initialValue: "")
        _note = State(initialValue: "")
    }

    /// Edit an existing session.
    init(editing pump: Pump, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Edit Pump"
        self.onSave = onSave
        let unit = AppState.shared.volumeUnit
        _timestamp = State(initialValue: pump.timestamp)
        // A session stored as a combined total opens in combined mode; otherwise per-side.
        if pump.combinedVolume != nil {
            _entryMode = State(initialValue: .combined)
        } else {
            _entryMode = State(initialValue: .perSide)
        }
        _leftText = State(initialValue: pump.leftVolume.map { unit.inputString(fromMilliliters: $0) } ?? "")
        _rightText = State(initialValue: pump.rightVolume.map { unit.inputString(fromMilliliters: $0) } ?? "")
        _combinedText = State(initialValue: pump.combinedVolume.map { unit.inputString(fromMilliliters: $0) } ?? "")
        if let duration = pump.duration {
            _durationText = State(initialValue: String(Int((duration / 60).rounded())))
        } else {
            _durationText = State(initialValue: "")
        }
        _note = State(initialValue: pump.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Volume") {
                    Picker("Entry", selection: $entryMode) {
                        Text("Per side").tag(EntryMode.perSide)
                        Text("Total").tag(EntryMode.combined)
                    }
                    .pickerStyle(.segmented)

                    if entryMode == .perSide {
                        volumeRow("Left", text: $leftText)
                        volumeRow("Right", text: $rightText)
                    } else {
                        volumeRow("Total", text: $combinedText)
                    }
                }

                if let total = totalMilliliters {
                    Section {
                        HStack {
                            Text("Total expressed")
                            Spacer()
                            Text(unit.formatted(fromMilliliters: total))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Duration") {
                    HStack {
                        TextField("Optional", text: $durationText)
                            .keyboardType(.numberPad)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Time") {
                    DatePicker(
                        "Pumped at",
                        selection: $timestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...3)
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
                        onSave(makeDraft())
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func volumeRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(unit.abbreviation)
                .foregroundStyle(.secondary)
        }
    }

    /// Live total in canonical milliliters for the readout, honoring the entry mode.
    private var totalMilliliters: Double? {
        switch entryMode {
        case .combined:
            return milliliters(combinedText)
        case .perSide:
            let sum = (milliliters(leftText) ?? 0) + (milliliters(rightText) ?? 0)
            return sum > 0 ? sum : nil
        }
    }

    private func makeDraft() -> Draft {
        switch entryMode {
        case .perSide:
            return Draft(
                timestamp: timestamp,
                leftVolume: milliliters(leftText),
                rightVolume: milliliters(rightText),
                combinedVolume: nil,
                duration: durationSeconds(),
                note: note
            )
        case .combined:
            return Draft(
                timestamp: timestamp,
                leftVolume: nil,
                rightVolume: nil,
                combinedVolume: milliliters(combinedText),
                duration: durationSeconds(),
                note: note
            )
        }
    }

    /// Parses an entered amount (in the preferred unit) to canonical milliliters,
    /// or nil when blank / not a positive number.
    private func milliliters(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return unit.toMilliliters(value)
    }

    /// Entered minutes converted to seconds, or nil when blank / not positive.
    private func durationSeconds() -> TimeInterval? {
        guard let minutes = Int(durationText), minutes > 0 else { return nil }
        return TimeInterval(minutes * 60)
    }
}
