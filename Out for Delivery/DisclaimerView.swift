//
//  DisclaimerView.swift
//  Out for Delivery
//

import SwiftUI

struct DisclaimerView: View {
    var onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A timing aid, not a medical device.")
                        .font(.title2.weight(.semibold))

                    Text("Out for Delivery times contractions so you can share clear numbers with your provider. It does not give medical advice, and it does not alert anyone when something might be urgent.")

                    Text("Follow your provider's instructions. In an emergency, call your provider or local emergency services.")

                    Divider()

                    Text("Your data")
                        .font(.headline)

                    Text("Contractions are stored on this device and synced through your private iCloud (your own Apple account, no third parties). You can turn iCloud off for this app in **Settings → Apple ID → iCloud** to keep data on this device only.")

                    Text("Use **Export tracking history** in the toolbar to send a CSV out of iCloud yourself.")
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Got it") {
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    DisclaimerView { }
}
