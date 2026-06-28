//
//  LoggedByLabel.swift
//  Out for Delivery
//
//  The quiet "Logged by NAME" attribution line shared by the contraction and feed
//  rows. Renders nothing when the name is absent (solo users), so shared logs read
//  as collaborative without cluttering solo use.
//

import SwiftUI

struct LoggedByLabel: View {
    let name: String?

    var body: some View {
        if let name, !name.isEmpty {
            Text("Logged by \(name)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
