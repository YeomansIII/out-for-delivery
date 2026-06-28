//
//  EditFeedView.swift
//  Out for Delivery
//
//  Bottom-sheet editor for a feed, rebuilt to the improved "Log feed" design
//  (design frame 02). Two modes via a Bottle / Nursing segmented control:
//
//  - **Bottle** — a large +/- volume stepper with quick presets and an inline
//    ml/oz unit toggle, plus a Formula / Breast milk selector (story 8.7).
//  - **Nursing** — minutes on each side entered with +/- steppers (story 8.2;
//    the live tap-a-side timer in frame 03 is deferred).
//
//  Plus an editable time and an optional note (story 8.11). Works in two modes:
//
//  - **Create** (`init(creating:)`): edits an in-memory draft and reports it on
//    Save; the caller inserts the feed only on confirm, so logging never races the
//    sheet presentation (no insert-driven fetch / CloudKit churn while appearing).
//  - **Edit** (`init(editing:)`): pre-filled from an existing feed.
//
//  Volumes are entered/displayed in the app-wide preferred unit and stored
//  canonically as milliliters. Newborn events are routinely backfilled and
//  corrected, so editing is first-class.
//

import SwiftUI

struct EditFeedView: View {
    /// The values the editor collects; the caller decides whether to insert or update.
    struct Draft {
        var timestamp: Date
        var kind: FeedKind
        var volume: Double?          // canonical milliliters
        var bottle: BottleContent?
        var leftMinutes: Int?
        var rightMinutes: Int?
        var note: String?
    }

    /// The two feed modes the sheet offers. `FeedKind.unspecified` is legacy-only
    /// and isn't selectable here; an unspecified feed opens as a bottle.
    private enum Mode: Hashable {
        case bottle
        case nursing

        var feedKind: FeedKind { self == .bottle ? .bottle : .breast }
    }

    private let navTitle: String
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var appState = AppState.shared

    @State private var timestamp: Date
    @State private var mode: Mode
    /// Bottle volume in canonical milliliters; 0 means "no amount recorded".
    @State private var volumeML: Double
    @State private var bottle: BottleContent?
    @State private var leftMinutes: Int
    @State private var rightMinutes: Int
    @State private var note: String

    private var unit: VolumeUnit { appState.volumeUnit }

    /// Create a new feed of `kind`, defaulting to now with no amount yet.
    init(creating kind: FeedKind, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Log Feed"
        self.onSave = onSave
        _timestamp = State(initialValue: Date())
        _mode = State(initialValue: kind == .breast ? .nursing : .bottle)
        _volumeML = State(initialValue: 0)
        _bottle = State(initialValue: nil)
        _leftMinutes = State(initialValue: 0)
        _rightMinutes = State(initialValue: 0)
        _note = State(initialValue: "")
    }

    /// Edit an existing feed.
    init(editing feed: Feed, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Edit Feed"
        self.onSave = onSave
        _timestamp = State(initialValue: feed.timestamp)
        _mode = State(initialValue: feed.feedKind == .breast ? .nursing : .bottle)
        _volumeML = State(initialValue: feed.volume ?? 0)
        _bottle = State(initialValue: feed.bottle)
        _leftMinutes = State(initialValue: feed.leftMinutes ?? 0)
        _rightMinutes = State(initialValue: feed.rightMinutes ?? 0)
        _note = State(initialValue: feed.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $mode) {
                        Text("Bottle").tag(Mode.bottle)
                        Text("Nursing").tag(Mode.nursing)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                if mode == .bottle {
                    Section { volumeControl }
                    Section("Type") { typeSelector }
                } else {
                    Section("Time on each side") {
                        minutesStepper("Left", value: $leftMinutes)
                        minutesStepper("Right", value: $rightMinutes)
                    }
                }

                Section("Time") {
                    DatePicker(
                        "Fed at",
                        selection: $timestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Note") {
                    TextField("Optional — latch, spit-up, fussiness", text: $note, axis: .vertical)
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
    }

    // MARK: - Bottle volume

    private var volumeControl: some View {
        VStack(spacing: 16) {
            HStack(spacing: 28) {
                stepButton(systemName: "minus") {
                    volumeML = max(0, volumeML - stepML)
                }
                .tint(.secondary)

                VStack(spacing: 0) {
                    Text(unit.inputString(fromMilliliters: volumeML))
                        .font(.system(size: 54, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(unit.abbreviation)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 120)
                .animation(.snappy, value: volumeML)

                stepButton(systemName: "plus") {
                    volumeML += stepML
                }
                .tint(NewbornEvent.feed.tint)
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

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private func presetChip(_ ml: Double) -> some View {
        let isSelected = abs(volumeML - ml) < 0.5
        return Button {
            volumeML = ml
        } label: {
            Text(unit.inputString(fromMilliliters: ml))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .frame(minWidth: 34)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? NewbornEvent.feed.tint : .secondary)
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

    /// Step size in canonical ml, sized to the entry unit (5 ml, or ~½ oz).
    private var stepML: Double {
        unit == .ounces ? unit.toMilliliters(0.5) : 5
    }

    /// Quick presets in canonical ml, derived from the entry unit's common amounts.
    private var presetsML: [Double] {
        let values: [Double] = unit == .ounces ? [2, 3, 4] : [60, 90, 120]
        return values.map { unit.toMilliliters($0) }
    }

    // MARK: - Bottle type (formula vs expressed breast milk)

    private var typeSelector: some View {
        HStack(spacing: 10) {
            ForEach(BottleContent.allCases, id: \.self) { content in
                let isSelected = bottle == content
                Button {
                    bottle = isSelected ? nil : content
                } label: {
                    Text(content.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(isSelected ? NewbornEvent.feed.tint : .secondary)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - Nursing minutes

    private func minutesStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...240) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.body.monospacedDigit())
                Text("min")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Save

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button {
                onSave(makeDraft())
                dismiss()
            } label: {
                Text("Save feed")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(NewbornEvent.feed.tint)
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

    private func makeDraft() -> Draft {
        switch mode {
        case .bottle:
            return Draft(
                timestamp: timestamp,
                kind: .bottle,
                volume: volumeML > 0 ? volumeML : nil,
                bottle: bottle,
                leftMinutes: nil,
                rightMinutes: nil,
                note: note
            )
        case .nursing:
            return Draft(
                timestamp: timestamp,
                kind: .breast,
                volume: nil,
                bottle: nil,
                leftMinutes: leftMinutes > 0 ? leftMinutes : nil,
                rightMinutes: rightMinutes > 0 ? rightMinutes : nil,
                note: note
            )
        }
    }
}
