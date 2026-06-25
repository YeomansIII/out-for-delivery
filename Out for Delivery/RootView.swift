//
//  RootView.swift
//  Out for Delivery
//
//  Top-level router. Chooses between labor (contraction timer) and newborn modes,
//  owns the baby-profile sheets, and keeps the active baby selection valid.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Query(sort: \Baby.createdAt, order: .forward) private var allBabies: [Baby]

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
            switch which {
            case .addBaby: BabyFormView(baby: nil)
            case .manageBabies: BabyManagerView()
            }
        }
        .task(id: babies.map(\.id)) {
            reconcileActiveBaby()
        }
    }

    /// Keep `activeBabyID` pointing at a real, non-archived baby and drop to labor
    /// mode if every baby has been archived/removed.
    private func reconcileActiveBaby() {
        if let id = appState.activeBabyID, babies.contains(where: { $0.id == id }) {
            return
        }
        appState.activeBabyID = babies.first?.id
        if !hasBabies { appState.mode = .labor }
    }
}
