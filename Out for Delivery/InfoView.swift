//
//  InfoView.swift
//  Out for Delivery
//

import SwiftUI
import ActivityKit

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    Text("Out for Delivery is a timing aid for contractions. It does not give medical advice or alerts.")
                    Text("Follow your provider's instructions. In an emergency, call your provider or local emergency services.")
                }

                Section("Timing conventions") {
                    labeled("Duration", "How long a contraction lasts (end − start).")
                    labeled("Frequency", "Start of one to start of the next.")
                    labeled("5-1-1", "≤5 min apart, ≥1 min long, sustained for ≥1 hour. A passive readout only.")
                }

                Section("Your data") {
                    Text("Contractions are stored on this device and synced through your private iCloud (your own Apple account, no third parties).")
                    Text("Disable iCloud for this app in Settings → Apple ID → iCloud to keep data on-device only.")
                    Text("CSV export is the only path that moves data outside iCloud.")
                }

                Section("Lock Screen Live Activity") {
                    let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
                    Label(
                        enabled ? "Live Activities are enabled" : "Live Activities are disabled",
                        systemImage: enabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(enabled ? .green : .orange)
                    if !enabled {
                        Text("Enable in Settings → Face ID & Passcode → Live Activities, and the app's own Live Activities toggle.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Activities last up to 8 hours and may need a quick app open to refresh.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    InfoView()
}
