//
//  BabyManagerView.swift
//  Out for Delivery
//
//  List, select, edit, and archive baby profiles. Tapping a baby makes it the
//  active baby for newborn mode.
//

import SwiftUI
import SwiftData

struct BabyManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appState = AppState.shared

    @Query(sort: \Baby.createdAt, order: .forward) private var allBabies: [Baby]

    @State private var sheet: BabySheet?

    private var activeBabies: [Baby] { allBabies.filter { !$0.isArchived } }
    private var archivedBabies: [Baby] { allBabies.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                Section("Babies") {
                    if activeBabies.isEmpty {
                        Text("No babies yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeBabies) { baby in
                            babyRow(baby)
                        }
                    }
                }

                if !archivedBabies.isEmpty {
                    Section("Archived") {
                        ForEach(archivedBabies) { baby in
                            HStack {
                                Text(baby.name)
                                Spacer()
                                Button("Restore") { baby.isArchived = false }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Babies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .add } label: {
                        Label("Add Baby", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .add: BabyFormView(baby: nil)
                case .edit(let baby): BabyFormView(baby: baby)
                }
            }
        }
    }

    private func babyRow(_ baby: Baby) -> some View {
        Button {
            appState.activeBabyID = baby.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(baby.name)
                        .foregroundStyle(.primary)
                    Text(baby.ageDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if baby.id == appState.activeBabyID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Archive", role: .destructive) { archive(baby) }
            Button("Edit") { sheet = .edit(baby) }
                .tint(.blue)
        }
    }

    private func archive(_ baby: Baby) {
        baby.isArchived = true
        if appState.activeBabyID == baby.id {
            appState.activeBabyID = activeBabies.first(where: { $0.id != baby.id })?.id
        }
    }
}

private enum BabySheet: Identifiable {
    case add
    case edit(Baby)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let baby): return baby.id.uuidString
        }
    }
}
