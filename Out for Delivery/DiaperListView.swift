//
//  DiaperListView.swift
//  Out for Delivery
//
//  The full diaper log for one baby (Epic 10): today's wet/dirty tally and time
//  since the last change at the top, then the recent changes with tap-to-edit and
//  swipe-to-delete. A toolbar "+" adds a past or live change. Pushed from the
//  dashboard's recent diaper tile.
//

import SwiftUI
import CoreData

struct DiaperListView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var diapers: FetchedResults<Diaper>

    @State private var sheet: DiaperSheet?

    /// Create mode carries no model (the change is inserted only on Save); edit mode
    /// keys on the stable `Diaper.id` so a temporary→permanent objectID swap on save
    /// can't dismiss the sheet.
    private enum DiaperSheet: Identifiable {
        case create
        case edit(Diaper)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let diaper): return "edit-\(diaper.id.uuidString)"
            }
        }
    }

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let id = baby.id
        _diapers = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
            predicate: NSPredicate(format: "babyID == %@", id as CVarArg)
        )
    }

    private var lastDiaper: Diaper? { diapers.first }

    var body: some View {
        List {
            statusSection
            if !diapers.isEmpty { recentSection }
        }
        .navigationTitle("Diapers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheet = .create
                } label: {
                    Label("Log diaper", systemImage: "plus")
                }
            }
        }
        .overlay {
            if diapers.isEmpty {
                ContentUnavailableView(
                    "No changes logged",
                    systemImage: "drop",
                    description: Text("Tap + to log a diaper change.")
                )
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .create:
                EditDiaperView(creating: .wet) { draft in
                    DiaperService.shared.addDiaper(
                        for: baby.id,
                        timestamp: draft.timestamp,
                        kind: draft.kind,
                        color: draft.color,
                        consistency: draft.consistency,
                        note: draft.note
                    )
                }
            case .edit(let diaper):
                EditDiaperView(editing: diaper) { draft in
                    DiaperService.shared.update(
                        diaper,
                        timestamp: draft.timestamp,
                        kind: draft.kind,
                        color: draft.color,
                        consistency: draft.consistency,
                        note: draft.note
                    )
                }
            }
        }
    }

    private var statusSection: some View {
        Section("Today") {
            let counts = DiaperService.shared.todayCounts(for: baby.id)
            HStack {
                tally(counts.wet, label: "wet")
                Divider()
                tally(counts.dirty, label: "dirty")
                if let last = lastDiaper {
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

    private func tally(_ value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentSection: some View {
        Section("Recent") {
            ForEach(diapers) { diaper in
                DiaperRowView(
                    diaper: diaper,
                    onEdit: { sheet = .edit(diaper) },
                    onDelete: { DiaperService.shared.delete(diaper) }
                )
            }
        }
    }
}

/// One logged diaper change in the recent list. Tap to edit, swipe to delete.
struct DiaperRowView: View {
    let diaper: Diaper
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: diaper.diaperKind.symbolName)
                .foregroundStyle(NewbornEvent.diaper.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(detailText)
                    .font(.body)
                Text(TimeFormatting.clock(diaper.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LoggedByLabel(name: diaper.loggedByName)
            }

            Spacer(minLength: 0)

            Text(diaper.timestamp, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(detailText) at \(TimeFormatting.clock(diaper.timestamp))")
        .accessibilityHint("Double tap to edit")
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// "Wet", "Dirty · yellow, seedy", "Both · green", etc.
    private var detailText: String {
        var parts: [String] = []
        if let color = diaper.diaperColor { parts.append(color.label.lowercased()) }
        if let consistency = diaper.diaperConsistency { parts.append(consistency.label.lowercased()) }
        return parts.isEmpty ? diaper.diaperKind.label : "\(diaper.diaperKind.label) · \(parts.joined(separator: ", "))"
    }
}
