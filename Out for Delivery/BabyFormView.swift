//
//  BabyFormView.swift
//  Out for Delivery
//
//  Create or edit a baby profile. Creating the first baby switches the app to
//  newborn mode (via AppState.onBabyCreated).
//

import SwiftUI
import SwiftData

struct BabyFormView: View {
    /// `nil` → creating a new baby; non-nil → editing an existing one.
    let baby: Baby?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let appState = AppState.shared

    @State private var name: String = ""
    @State private var birthDate: Date = Date()

    private var isEditing: Bool { baby != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    DatePicker(
                        "Born",
                        selection: $birthDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if isEditing, let baby {
                    Section {
                        Text(baby.ageDescription)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Baby" : "Add Baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let baby {
                    name = baby.name
                    birthDate = baby.birthDate
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let baby {
            baby.name = trimmed
            baby.birthDate = birthDate
        } else {
            let newBaby = Baby(name: trimmed, birthDate: birthDate)
            modelContext.insert(newBaby)
            appState.onBabyCreated(newBaby)
        }
        dismiss()
    }
}
