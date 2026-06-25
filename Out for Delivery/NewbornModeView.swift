//
//  NewbornModeView.swift
//  Out for Delivery
//
//  Newborn-mode home. For now a placeholder dashboard showing the active baby and
//  a quick-switch / management menu; feed, diaper, and pump tracking arrive in
//  later epics.
//

import SwiftUI
import SwiftData

struct NewbornModeView: View {
    @State private var appState = AppState.shared
    @Query(sort: \Baby.createdAt, order: .forward) private var allBabies: [Baby]

    private var babies: [Baby] { allBabies.filter { !$0.isArchived } }
    private var activeBaby: Baby? {
        babies.first(where: { $0.id == appState.activeBabyID }) ?? babies.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let baby = activeBaby {
                    dashboard(for: baby)
                } else {
                    ContentUnavailableView(
                        "No baby selected",
                        systemImage: "figure.child",
                        description: Text("Add a baby to start tracking.")
                    )
                }
            }
            .navigationTitle(activeBaby?.name ?? "Baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    private func dashboard(for baby: Baby) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(baby.name)
                        .font(.title2.weight(.semibold))
                    Text(baby.ageDescription)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            FeedSectionView(baby: baby)

            Section("More tracking") {
                comingSoonRow("Diapers", systemImage: "humidity.fill")
                comingSoonRow("Pumping", systemImage: "waveform.path.ecg")
            }
        }
    }

    private func comingSoonRow(_ title: String, systemImage: String) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(.secondary)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            @Bindable var appState = appState
            Menu {
                if babies.count > 1 {
                    Picker("Active Baby", selection: $appState.activeBabyID) {
                        ForEach(babies) { baby in
                            Text(baby.name).tag(Optional(baby.id))
                        }
                    }
                    Divider()
                }
                ModeMenuButtons()
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}
