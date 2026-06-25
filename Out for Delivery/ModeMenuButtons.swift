//
//  ModeMenuButtons.swift
//  Out for Delivery
//
//  Shared menu content embedded in both modes' toolbars: switch between labor
//  and newborn modes, add a baby, and manage babies.
//

import SwiftUI
import SwiftData

struct ModeMenuButtons: View {
    @State private var appState = AppState.shared
    @Query private var allBabies: [Baby]

    private var babies: [Baby] { allBabies.filter { !$0.isArchived } }
    private var hasBabies: Bool { !babies.isEmpty }

    var body: some View {
        if hasBabies {
            Button {
                appState.mode = (appState.mode == .labor) ? .newborn : .labor
            } label: {
                if appState.mode == .labor {
                    Label("Switch to Baby Tracking", systemImage: "figure.child")
                } else {
                    Label("Switch to Contraction Timer", systemImage: "stopwatch")
                }
            }
            Button {
                appState.sheet = .manageBabies
            } label: {
                Label("Manage Babies", systemImage: "person.2")
            }
        }
        Button {
            appState.sheet = .addBaby
        } label: {
            Label("Add Baby", systemImage: "plus")
        }
    }
}
