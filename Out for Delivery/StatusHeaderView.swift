//
//  StatusHeaderView.swift
//  Out for Delivery
//

import SwiftUI

struct StatusHeaderView: View {
    let snapshot: ContractionService.Snapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: phaseIcon)
                .font(.callout)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(themedLine)
                    .font(.callout.weight(.medium))
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Content-layer card: standard material per HIG, which reserves Liquid Glass
        // for the floating control / navigation layer (the Start/Stop controls).
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    private var phaseIcon: String {
        if snapshot.count == 0 { return "shippingbox" }
        switch snapshot.phase {
        case .contracting: return "shippingbox.and.arrow.backward.fill"
        case .resting: return snapshot.patternMet ? "checkmark.seal.fill" : "shippingbox.fill"
        }
    }

    private var themedLine: String {
        if snapshot.count == 0 { return "Order placed" }
        if snapshot.patternMet { return "Arriving soon" }
        switch snapshot.phase {
        case .contracting: return "Out for delivery"
        case .resting: return "In transit"
        }
    }

    private var detailLine: String {
        snapshot.patternMet ? "5-1-1: met" : "5-1-1: not yet"
    }
}
