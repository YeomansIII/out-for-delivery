//
//  EditPumpView.swift
//  Out for Delivery
//
//  Bottom-sheet editor for a pump session (Epic 9, design frame 05): volume expressed
//  — per side (left / right) or as one combined total — plus an optional duration and
//  note. Styled to match the "Log feed" sheet (EditFeedView / frame 02): big +/- volume
//  steppers, a tinted derived-total highlight, an inline "Time it" live timer (story 9.2),
//  and a Liquid Glass "Save pump" bar with caregiver attribution. Volumes are entered /
//  displayed in the app-wide preferred unit (ml or oz) and stored canonically as ml.
//
//  Create / Edit follow the same draft pattern as EditFeedView: the caller inserts the
//  session only on confirm, so logging never races the sheet presentation.
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
    @State private var appState = AppState.shared

    @State private var timestamp: Date
    @State private var entryMode: EntryMode
    /// Volumes in canonical milliliters; 0 means "no amount recorded".
    @State private var leftML: Double
    @State private var rightML: Double
    @State private var combinedML: Double
    @State private var durationMinutes: Int
    @State private var note: String
    /// When the live "Time it" timer is running (story 9.2); nil when stopped. On stop the
    /// measured minutes fill `durationMinutes`, so the existing save path is unchanged.
    @State private var timingStart: Date?

    private var unit: VolumeUnit { appState.volumeUnit }

    /// Create a new session, defaulting to per-side entry at now.
    init(creating: Void = (), onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Log Pump"
        self.onSave = onSave
        _timestamp = State(initialValue: Date())
        _entryMode = State(initialValue: .perSide)
        _leftML = State(initialValue: 0)
        _rightML = State(initialValue: 0)
        _combinedML = State(initialValue: 0)
        _durationMinutes = State(initialValue: 0)
        _note = State(initialValue: "")
    }

    /// Edit an existing session.
    init(editing pump: Pump, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Edit Pump"
        self.onSave = onSave
        _timestamp = State(initialValue: pump.timestamp)
        // A session stored as a combined total opens in combined mode; otherwise per-side.
        _entryMode = State(initialValue: pump.combinedVolume != nil ? .combined : .perSide)
        _leftML = State(initialValue: pump.leftVolume ?? 0)
        _rightML = State(initialValue: pump.rightVolume ?? 0)
        _combinedML = State(initialValue: pump.combinedVolume ?? 0)
        _durationMinutes = State(initialValue: pump.duration.map { Int(($0 / 60).rounded()) } ?? 0)
        _note = State(initialValue: pump.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry", selection: $entryMode) {
                        Text("Per side").tag(EntryMode.perSide)
                        Text("Total").tag(EntryMode.combined)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                if entryMode == .perSide {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            sideCard("Left", value: $leftML)
                            sideCard("Right", value: $rightML)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                        HStack {
                            Spacer()
                            unitToggle
                        }
                        .listRowBackground(Color.clear)
                    }

                    if let total = totalMilliliters {
                        Section { totalHighlight(total) }
                    }
                } else {
                    Section { combinedControl }
                }

                Section("Duration") { durationControl }

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
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact, trigger: timingStart)
    }

    // MARK: - Per-side volume cards (design frame 05)

    private func sideCard(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(unit.inputString(fromMilliliters: value.wrappedValue))
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(unit.abbreviation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy, value: value.wrappedValue)

            HStack(spacing: 8) {
                flexStep("minus", tint: .secondary) {
                    value.wrappedValue = max(0, value.wrappedValue - stepML)
                }
                flexStep("plus", tint: NewbornEvent.pump.tint) {
                    value.wrappedValue += stepML
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func flexStep(_ systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    // MARK: - Combined volume control (matches the bottle stepper in EditFeedView)

    private var combinedControl: some View {
        VStack(spacing: 16) {
            HStack(spacing: 28) {
                circleStep("minus") {
                    combinedML = max(0, combinedML - stepML)
                }
                .tint(.secondary)

                VStack(spacing: 0) {
                    Text(unit.inputString(fromMilliliters: combinedML))
                        .font(.system(size: 54, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(unit.abbreviation)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 120)
                .animation(.snappy, value: combinedML)

                circleStep("plus") {
                    combinedML += stepML
                }
                .tint(NewbornEvent.pump.tint)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach(presetsML, id: \.self) { preset in
                    presetChip(preset)
                }
                Spacer(minLength: 0)
                unitToggle
            }
        }
        .padding(.vertical, 6)
    }

    private func circleStep(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private func presetChip(_ ml: Double) -> some View {
        let isSelected = abs(combinedML - ml) < 0.5
        return Button {
            combinedML = ml
        } label: {
            Text(unit.inputString(fromMilliliters: ml))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .frame(minWidth: 34)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? NewbornEvent.pump.tint : .secondary)
    }

    private var unitToggle: some View {
        Picker("Unit", selection: $appState.volumeUnit) {
            ForEach(VolumeUnit.allCases, id: \.self) { unit in
                Text(unit.abbreviation).tag(unit)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// The derived per-side total, shown as a tinted highlight (frame 05).
    private func totalHighlight(_ ml: Double) -> some View {
        HStack {
            Text("Total expressed")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(unit.formatted(fromMilliliters: ml))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(NewbornEvent.pump.tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(NewbornEvent.pump.tint.opacity(0.14), in: .rect(cornerRadius: 18))
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - Duration (manual minutes + live "Time it", story 9.2)

    @ViewBuilder
    private var durationControl: some View {
        if let start = timingStart {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch")
                    .foregroundStyle(NewbornEvent.pump.tint)
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.title3.monospacedDigit())
                Spacer()
                Button("Stop") { stopTiming() }
                    .buttonStyle(.borderedProminent)
                    .tint(NewbornEvent.pump.tint)
            }
        } else {
            Stepper(value: $durationMinutes, in: 0...240) {
                HStack {
                    Text("Length")
                    Spacer()
                    Text("\(durationMinutes)")
                        .font(.body.monospacedDigit())
                    Text("min")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                startTiming()
            } label: {
                Label("Time it", systemImage: "stopwatch")
            }
            .tint(NewbornEvent.pump.tint)
        }
    }

    private func startTiming() {
        timingStart = Date()
    }

    /// Stops the live timer and folds the elapsed time into the minutes field (the unit
    /// the field already uses). A sub-30s tap rounds to nothing.
    private func stopTiming() {
        guard let start = timingStart else { return }
        durationMinutes = Int((Date().timeIntervalSince(start) / 60).rounded())
        timingStart = nil
    }

    // MARK: - Save

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button {
                onSave(makeDraft())
                dismiss()
            } label: {
                Text("Save pump")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(NewbornEvent.pump.tint)
            .controlSize(.large)

            if let attribution {
                Text(attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.bar)
    }

    /// Quiet "Logging by NAME" line; nil for solo users (no name resolved).
    private var attribution: String? {
        guard let name = CurrentUserIdentity.shared.currentLoggedByName, !name.isEmpty else { return nil }
        return "Logging by \(name)"
    }

    /// Live total in canonical milliliters for the readout, honoring the entry mode.
    private var totalMilliliters: Double? {
        switch entryMode {
        case .combined:
            return combinedML > 0 ? combinedML : nil
        case .perSide:
            let sum = leftML + rightML
            return sum > 0 ? sum : nil
        }
    }

    private func makeDraft() -> Draft {
        let duration: TimeInterval? = durationMinutes > 0 ? TimeInterval(durationMinutes * 60) : nil
        switch entryMode {
        case .perSide:
            return Draft(
                timestamp: timestamp,
                leftVolume: leftML > 0 ? leftML : nil,
                rightVolume: rightML > 0 ? rightML : nil,
                combinedVolume: nil,
                duration: duration,
                note: note
            )
        case .combined:
            return Draft(
                timestamp: timestamp,
                leftVolume: nil,
                rightVolume: nil,
                combinedVolume: combinedML > 0 ? combinedML : nil,
                duration: duration,
                note: note
            )
        }
    }

    /// Step size in canonical ml, sized to the entry unit (5 ml, or ~½ oz) — matches the
    /// bottle stepper in EditFeedView.
    private var stepML: Double {
        unit == .ounces ? unit.toMilliliters(0.5) : 5
    }

    /// Quick presets in canonical ml for the combined total, derived from the unit.
    private var presetsML: [Double] {
        let values: [Double] = unit == .ounces ? [2, 4, 6] : [60, 120, 180]
        return values.map { unit.toMilliliters($0) }
    }
}
