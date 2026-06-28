//
//  FeedDetailView.swift
//  Out for Delivery
//
//  Hosts the full feed experience (status, log buttons, volume unit, feed-on-demand
//  reminder settings, recent feeds, CSV import/export) that FeedSectionView provides,
//  as a standalone screen pushed from the dashboard's feed tile. Keeps all the
//  shipped feed-management controls reachable now that the dashboard is a summary.
//

import SwiftUI

struct FeedDetailView: View {
    @ObservedObject var baby: Baby

    var body: some View {
        List {
            FeedSectionView(baby: baby)
        }
        .navigationTitle("Feeding")
        .navigationBarTitleDisplayMode(.inline)
    }
}
