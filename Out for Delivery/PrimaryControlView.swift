//
//  PrimaryControlView.swift
//  Out for Delivery
//

import SwiftUI

struct PrimaryControlView: View {
    let snapshot: ContractionService.Snapshot
    let onStart: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            liveCounter
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            switch snapshot.phase {
            case .contracting:
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.glass)

                    Button {
                        onStop()
                    } label: {
                        Text("Stop")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                }
            case .resting:
                Button {
                    onStart()
                } label: {
                    Text("Start")
                        .font(.title.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            }
        }
        .sensoryFeedback(.impact, trigger: snapshot.phase)
    }

    @ViewBuilder
    private var liveCounter: some View {
        switch snapshot.phase {
        case .contracting:
            if let start = snapshot.currentStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text("0:00")
            }
        case .resting:
            if let lastStart = snapshot.lastStart {
                Text(timerInterval: lastStart...Date.distantFuture, countsDown: false)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
