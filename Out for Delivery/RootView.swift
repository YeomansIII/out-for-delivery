//
//  RootView.swift
//  Out for Delivery
//
//  Top-level router. Chooses between labor (contraction timer) and newborn modes,
//  owns the baby-profile sheets, and keeps the active baby selection valid.
//

import SwiftUI
import CoreData

struct RootView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)]
    ) private var allBabies: FetchedResults<Baby>

    @State private var appState = AppState.shared

    private var babies: [Baby] { allBabies.filter { !$0.isArchived } }
    private var hasBabies: Bool { !babies.isEmpty }

    /// With no babies the app always shows labor mode, regardless of the stored preference.
    private var effectiveMode: AppMode { hasBabies ? appState.mode : .labor }

    var body: some View {
        @Bindable var appState = appState

        Group {
            switch effectiveMode {
            case .labor:
                ContentView()
            case .newborn:
                NewbornModeView()
            }
        }
        .sheet(item: $appState.sheet) { which in
            Group {
                switch which {
                case .addBaby: BabyFormView(baby: nil)
                case .manageBabies: BabyManagerView()
                case .family: FamilyView()
                }
            }
            .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
        }
        .task(id: babies.map(\.id)) {
            reconcileActiveBaby()
        }
    }

    /// Keep `activeBabyID` pointing at a real, non-archived baby and keep the mode in
    /// sync with whether any babies exist.
    private func reconcileActiveBaby() {
        if let id = appState.activeBabyID, babies.contains(where: { $0.id == id }) {
            return
        }
        // We aren't pointing at a valid baby. If babies exist (created here, or
        // arrived from a caregiver's shared baby), adopt the first one. When we
        // had none active before, land on the baby dashboard the same way creating a
        // baby does, so a caregiver who accepts a share sees the nursery, not the
        // contraction timer. A user who later switches back to labor keeps their
        // choice (this only runs when the active baby is missing).
        if let first = babies.first {
            let hadNoActiveBaby = appState.activeBabyID == nil
            appState.activeBabyID = first.id
            if hadNoActiveBaby { appState.mode = .newborn }
        } else {
            appState.activeBabyID = nil
            appState.mode = .labor
        }
    }
}
