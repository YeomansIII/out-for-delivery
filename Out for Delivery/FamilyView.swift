//
//  FamilyView.swift
//  Out for Delivery
//
//  Sharing overview: a single place to see what is shared and with whom. Lists the
//  contraction history and each baby with its current share status; tapping a row
//  opens that record's own share controls (RecordShareView), where you invite
//  caregivers, see the roster, and stop or leave the share.
//
//  Sharing is now per-record (each baby is its own share root, contractions share via
//  the per-user labor log), so this screen is just the directory into those controls.
//  This is content-layer UI: a standard List with standard materials.
//

import SwiftUI
import CoreData

struct FamilyView: View {
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)]
    ) private var allBabies: FetchedResults<Baby>

    /// The record whose share controls are presented, if any.
    @State private var target: ShareTarget?

    private var activeBabies: [Baby] { allBabies.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    overviewRow(
                        title: "Contraction history",
                        objectID: PersistenceController.shared.laborLog.objectID,
                        systemImage: "stopwatch"
                    )
                } header: {
                    Text("Contractions")
                } footer: {
                    Text("Share your contraction history with a partner so you both follow the same log.")
                }

                if !activeBabies.isEmpty {
                    Section {
                        ForEach(activeBabies) { baby in
                            overviewRow(
                                title: baby.name,
                                objectID: baby.objectID,
                                systemImage: "figure.child"
                            )
                        }
                    } header: {
                        Text("Babies")
                    } footer: {
                        Text("Each baby is shared on its own, so you can share one baby with a caregiver while another stays private.")
                    }
                }
            }
            .navigationTitle("Family & Caregivers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $target) { target in
                RecordShareView(target: target)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func overviewRow(title: String, objectID: NSManagedObjectID, systemImage: String) -> some View {
        let isShared = SharingManager.shared.isShared(objectID)
        return Button {
            target = ShareTarget(objectID: objectID, title: title)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(isShared ? "Shared" : "Just you")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isShared ? .green : .secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isShared ? "shared" : "not shared")")
        .accessibilityHint("Opens sharing controls")
    }
}
