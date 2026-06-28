//
//  PumpListView.swift
//  Out for Delivery
//
//  The full pump log for one baby (Epic 9): today's expressed total and time since
//  the last session at the top, then recent sessions with tap-to-edit and
//  swipe-to-delete. A toolbar "+" adds a past or live session. Pushed from the
//  dashboard's recent pump tile.
//

import SwiftUI
import CoreData

struct PumpListView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var pumps: FetchedResults<Pump>

    @State private var sheet: PumpSheet?

    private enum PumpSheet: Identifiable {
        case create
        case edit(Pump)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let pump): return "edit-\(pump.id.uuidString)"
            }
        }
    }

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let id = baby.id
        _pumps = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
            predicate: NSPredicate(format: "babyID == %@", id as CVarArg)
        )
    }

    private var lastPump: Pump? { pumps.first }

    var body: some View {
        List {
            statusSection
            if !pumps.isEmpty { recentSection }
        }
        .navigationTitle("Pumping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheet = .create
                } label: {
                    Label("Log pump", systemImage: "plus")
                }
            }
        }
        .overlay {
            if pumps.isEmpty {
                ContentUnavailableView(
                    "No sessions logged",
                    systemImage: "waveform.path.ecg",
                    description: Text("Tap + to log a pump session.")
                )
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .create:
                EditPumpView { draft in
                    PumpService.shared.addPump(
                        for: baby.id,
                        timestamp: draft.timestamp,
                        leftVolume: draft.leftVolume,
                        rightVolume: draft.rightVolume,
                        combinedVolume: draft.combinedVolume,
                        duration: draft.duration,
                        note: draft.note
                    )
                }
            case .edit(let pump):
                EditPumpView(editing: pump) { draft in
                    PumpService.shared.update(
                        pump,
                        timestamp: draft.timestamp,
                        leftVolume: draft.leftVolume,
                        rightVolume: draft.rightVolume,
                        combinedVolume: draft.combinedVolume,
                        duration: draft.duration,
                        note: draft.note
                    )
                }
            }
        }
    }

    private var statusSection: some View {
        Section("Today") {
            HStack {
                VStack(spacing: 2) {
                    Text(AppState.shared.volumeUnit.formatted(
                        fromMilliliters: PumpService.shared.todayTotalVolume(for: baby.id)))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text("expressed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                if let last = lastPump {
                    Divider()
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(spacing: 2) {
                            Text(TimeFormatting.elapsedShort(context.date.timeIntervalSince(last.timestamp)))
                                .font(.title3.weight(.semibold).monospacedDigit())
                            Text("since last")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var recentSection: some View {
        Section("Recent") {
            ForEach(pumps) { pump in
                PumpRowView(
                    pump: pump,
                    onEdit: { sheet = .edit(pump) },
                    onDelete: { PumpService.shared.delete(pump) }
                )
            }
        }
    }
}

/// One logged pump session in the recent list. Tap to edit, swipe to delete.
struct PumpRowView: View {
    let pump: Pump
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(NewbornEvent.pump.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(detailText)
                    .font(.body)
                Text(TimeFormatting.clock(pump.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LoggedByLabel(name: pump.loggedByName)
            }

            Spacer(minLength: 0)

            Text(pump.timestamp, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(detailText) at \(TimeFormatting.clock(pump.timestamp))")
        .accessibilityHint("Double tap to edit")
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// "155 ml · L 70 R 85 · 18 min", trimming whatever wasn't recorded.
    private var detailText: String {
        let unit = AppState.shared.volumeUnit
        var parts: [String] = []
        if let total = pump.totalVolume {
            parts.append(unit.formatted(fromMilliliters: total))
        }
        if pump.combinedVolume == nil {
            var sides: [String] = []
            if let left = pump.leftVolume { sides.append("L \(unit.inputString(fromMilliliters: left))") }
            if let right = pump.rightVolume { sides.append("R \(unit.inputString(fromMilliliters: right))") }
            if !sides.isEmpty { parts.append(sides.joined(separator: " ")) }
        }
        if let duration = pump.duration {
            parts.append("\(Int((duration / 60).rounded())) min")
        }
        return parts.isEmpty ? "Pump session" : parts.joined(separator: " · ")
    }
}
