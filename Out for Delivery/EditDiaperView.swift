//
//  EditDiaperView.swift
//  Out for Delivery
//
//  Bottom-sheet editor for a diaper change (Epic 10): kind (wet / dirty / both),
//  time, and — for a dirty change — optional color and consistency, plus an
//  optional note. Like EditFeedView it works in two modes:
//
//  - **Create** (`init(creating:)`): edits an in-memory draft and reports it on
//    Save; the caller inserts the change only on confirm, so logging never races
//    the sheet presentation.
//  - **Edit** (`init(editing:)`): pre-filled from an existing change.
//
//  Newborn events are routinely backfilled and corrected, so editing is first-class.
//

import SwiftUI

struct EditDiaperView: View {
    /// The values the editor collects; the caller decides whether to insert or update.
    struct Draft {
        var timestamp: Date
        var kind: DiaperKind
        var color: DiaperColor?
        var consistency: DiaperConsistency?
        var note: String?
    }

    private let navTitle: String
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var timestamp: Date
    @State private var kind: DiaperKind
    @State private var color: DiaperColor?
    @State private var consistency: DiaperConsistency?
    @State private var note: String

    /// Create a new change, defaulting to wet (the most common) at now.
    init(creating kind: DiaperKind = .wet, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Log Diaper"
        self.onSave = onSave
        _timestamp = State(initialValue: Date())
        _kind = State(initialValue: kind)
        _color = State(initialValue: nil)
        _consistency = State(initialValue: nil)
        _note = State(initialValue: "")
    }

    /// Edit an existing change.
    init(editing diaper: Diaper, onSave: @escaping (Draft) -> Void) {
        self.navTitle = "Edit Diaper"
        self.onSave = onSave
        _timestamp = State(initialValue: diaper.timestamp)
        _kind = State(initialValue: diaper.diaperKind)
        _color = State(initialValue: diaper.diaperColor)
        _consistency = State(initialValue: diaper.diaperConsistency)
        _note = State(initialValue: diaper.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(DiaperKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if kind.hasStool {
                    Section("Color") {
                        colorPicker
                    }
                    Section("Consistency") {
                        Picker("Consistency", selection: $consistency) {
                            Text("None").tag(DiaperConsistency?.none)
                            ForEach(DiaperConsistency.allCases, id: \.self) { value in
                                Text(value.label).tag(DiaperConsistency?.some(value))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Time") {
                    DatePicker(
                        "Changed at",
                        selection: $timestamp,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Note") {
                    TextField("Optional — blood, rash, etc.", text: $note, axis: .vertical)
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
                        onSave(Draft(
                            timestamp: timestamp,
                            kind: kind,
                            color: kind.hasStool ? color : nil,
                            consistency: kind.hasStool ? consistency : nil,
                            note: note
                        ))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// A row of tappable stool-color swatches with a selection ring (Epic 10.2).
    private var colorPicker: some View {
        HStack(spacing: 14) {
            ForEach(DiaperColor.allCases, id: \.self) { value in
                Button {
                    color = (color == value) ? nil : value
                } label: {
                    Circle()
                        .fill(value.swatch)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if value == .unknown {
                                Image(systemName: "questionmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(NewbornEvent.diaper.tint, lineWidth: color == value ? 3 : 0)
                                .padding(-3)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.label)
                .accessibilityAddTraits(color == value ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
