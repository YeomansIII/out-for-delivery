//
//  EditContractionView.swift
//  Out for Delivery
//
//  Bottom-sheet editor for adjusting a logged contraction's start time and length.
//

import SwiftUI

struct EditContractionView: View {
    let contraction: Contraction
    /// Called with the edited start date and end date (nil = in progress).
    let onSave: (Date, Date?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    /// Completed contractions have an editable length; an in-progress one does not.
    private let isInProgress: Bool
    @State private var durationMinutes: Int
    @State private var durationSeconds: Int

    init(contraction: Contraction, onSave: @escaping (Date, Date?) -> Void) {
        self.contraction = contraction
        self.onSave = onSave
        _startDate = State(initialValue: contraction.startDate)
        self.isInProgress = contraction.endDate == nil
        let total = Int((contraction.duration ?? 0).rounded())
        _durationMinutes = State(initialValue: total / 60)
        _durationSeconds = State(initialValue: total % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start time") {
                    DatePicker(
                        "Started",
                        selection: $startDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if !isInProgress {
                    Section("Length") {
                        HStack(spacing: 0) {
                            durationWheel(selection: $durationMinutes, unit: "min")
                            durationWheel(selection: $durationSeconds, unit: "sec")
                        }
                        .frame(maxHeight: 140)
                    }
                }
            }
            .navigationTitle("Edit Contraction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func durationWheel(selection: Binding<Int>, unit: String) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<60, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
    }

    private func save() {
        let endDate: Date?
        if isInProgress {
            endDate = nil
        } else {
            let length = TimeInterval(durationMinutes * 60 + durationSeconds)
            endDate = startDate.addingTimeInterval(length)
        }
        onSave(startDate, endDate)
        dismiss()
    }
}
