//
//  TimelineView.swift
//  Out for Delivery
//
//  The unified, cross-type timeline for one baby (Epic 11.3–11.5, 11.7; design
//  frame 07). Merges feeds, diapers, and pumps into one day-grouped, newest-first
//  list with type-filter chips, per-entry caregiver attribution, tap-to-edit, and
//  swipe-to-delete. An "Add past" menu logs a past event of any type. Reached from
//  the newborn-mode bottom tab bar.
//
//  Visual language follows the design baseline with native iOS 26 SwiftUI: solid,
//  legible rows for the medical numbers (monospaced digits) and Liquid Glass on the
//  filter chips, matching the dashboard's quick-log buttons.
//

import SwiftUI
import CoreData

struct BabyTimelineView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var feeds: FetchedResults<Feed>
    @FetchRequest private var diapers: FetchedResults<Diaper>
    @FetchRequest private var pumps: FetchedResults<Pump>

    @State private var filter: TimelineFilter = .all
    @State private var sheet: TimelineSheet?

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let id = baby.id
        let newestFirst = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let predicate = NSPredicate(format: "babyID == %@", id as CVarArg)
        _feeds = FetchRequest(sortDescriptors: newestFirst, predicate: predicate)
        _diapers = FetchRequest(sortDescriptors: newestFirst, predicate: predicate)
        _pumps = FetchRequest(sortDescriptors: newestFirst, predicate: predicate)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            listOrEmpty
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .createFeed } label: {
                        Label("Feed", systemImage: NewbornEvent.feed.symbolName)
                    }
                    Button { sheet = .createDiaper } label: {
                        Label("Diaper", systemImage: NewbornEvent.diaper.symbolName)
                    }
                    Button { sheet = .createPump } label: {
                        Label("Pump", systemImage: NewbornEvent.pump.symbolName)
                    }
                } label: {
                    Label("Add past", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheet) { which in
            sheetContent(which)
        }
    }

    // MARK: - Filter chips

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimelineFilter.allCases) { chip($0) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func chip(_ option: TimelineFilter) -> some View {
        let selected = filter == option
        let button = Button {
            withAnimation(.snappy) { filter = option }
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 2)
        }
        if selected {
            button.buttonStyle(.glassProminent).tint(option.tint ?? .accentColor)
        } else {
            button.buttonStyle(.glass)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listOrEmpty: some View {
        if dayGroups.isEmpty {
            emptyView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            List {
                ForEach(dayGroups, id: \.day) { group in
                    Section(dayHeader(group.day)) {
                        ForEach(group.items) { item in
                            TimelineRowView(
                                item: item,
                                onEdit: { sheet = editSheet(for: item) },
                                onDelete: { delete(item) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyView: some View {
        let title: String
        switch filter {
        case .all: title = "No events logged"
        case .feeds: title = "No feeds logged"
        case .diapers: title = "No diapers logged"
        case .pumps: title = "No pumps logged"
        }
        return ContentUnavailableView(
            title,
            systemImage: "clock.arrow.circlepath",
            description: Text("Logged events appear here. Tap + to add a past event.")
        )
    }

    // MARK: - Merge / filter / group

    /// All visible events for the active filter, newest first. The three fetches are
    /// each pre-sorted; a merged sort keeps the interleaving simple and the volumes small.
    private var items: [TimelineItem] {
        var result: [TimelineItem] = []
        if filter.includes(.feed) { result += feeds.map(TimelineItem.feed) }
        if filter.includes(.diaper) { result += diapers.map(TimelineItem.diaper) }
        if filter.includes(.pump) { result += pumps.map(TimelineItem.pump) }
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// `items` grouped by calendar day, preserving newest-first order. An ordered
    /// array (not a Dictionary) keeps the day sections stable.
    private var dayGroups: [(day: Date, items: [TimelineItem])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [TimelineItem]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.timestamp)
            if byDay[day] == nil {
                order.append(day)
                byDay[day] = []
            }
            byDay[day]?.append(item)
        }
        return order.map { (day: $0, items: byDay[$0] ?? []) }
    }

    private func dayHeader(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Edit / delete routing

    private func editSheet(for item: TimelineItem) -> TimelineSheet {
        switch item {
        case .feed(let feed): return .editFeed(feed)
        case .diaper(let diaper): return .editDiaper(diaper)
        case .pump(let pump): return .editPump(pump)
        }
    }

    private func delete(_ item: TimelineItem) {
        switch item {
        case .feed(let feed): FeedService.shared.delete(feed)
        case .diaper(let diaper): DiaperService.shared.delete(diaper)
        case .pump(let pump): PumpService.shared.delete(pump)
        }
    }

    // MARK: - Editors (reuse the same editors + services as the per-type logs)

    @ViewBuilder
    private func sheetContent(_ which: TimelineSheet) -> some View {
        switch which {
        case .createFeed:
            EditFeedView(creating: .bottle) { draft in
                FeedService.shared.addFeed(
                    for: baby.id,
                    timestamp: draft.timestamp,
                    kind: draft.kind,
                    volume: draft.volume,
                    bottle: draft.bottle,
                    leftMinutes: draft.leftMinutes,
                    rightMinutes: draft.rightMinutes,
                    note: draft.note
                )
            }
        case .editFeed(let feed):
            EditFeedView(editing: feed) { draft in
                FeedService.shared.update(
                    feed,
                    timestamp: draft.timestamp,
                    kind: draft.kind,
                    volume: draft.volume,
                    bottle: draft.bottle,
                    leftMinutes: draft.leftMinutes,
                    rightMinutes: draft.rightMinutes,
                    note: draft.note
                )
            }
        case .createDiaper:
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
        case .editDiaper(let diaper):
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
        case .createPump:
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
        case .editPump(let pump):
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

// MARK: - Filter

/// The timeline's type filter. `All` is the default; each other case maps to one
/// `NewbornEvent` and is tinted with that event's color.
enum TimelineFilter: CaseIterable, Identifiable {
    case all, feeds, diapers, pumps

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .feeds: return "Feeds"
        case .diapers: return "Diapers"
        case .pumps: return "Pumps"
        }
    }

    var event: NewbornEvent? {
        switch self {
        case .all: return nil
        case .feeds: return .feed
        case .diapers: return .diaper
        case .pumps: return .pump
        }
    }

    var tint: Color? { event?.tint }

    /// Whether an event of this type is shown under the current filter.
    func includes(_ candidate: NewbornEvent) -> Bool {
        event == nil || event == candidate
    }
}

// MARK: - Unified item

/// A single timeline entry wrapping one of the three managed objects. It carries the
/// live object (the editors and services need it) and computes display values lazily,
/// so edits stay in sync with the shared view context. Not Sendable (wraps an
/// NSManagedObject) — built and read only on the main actor.
enum TimelineItem: Identifiable {
    case feed(Feed)
    case diaper(Diaper)
    case pump(Pump)

    /// Type-prefixed and keyed on the model's stable UUID (never the objectID, which
    /// swaps temporary→permanent on save).
    var id: String {
        switch self {
        case .feed(let feed): return "feed-\(feed.id.uuidString)"
        case .diaper(let diaper): return "diaper-\(diaper.id.uuidString)"
        case .pump(let pump): return "pump-\(pump.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case .feed(let feed): return feed.timestamp
        case .diaper(let diaper): return diaper.timestamp
        case .pump(let pump): return pump.timestamp
        }
    }

    var event: NewbornEvent {
        switch self {
        case .feed: return .feed
        case .diaper: return .diaper
        case .pump: return .pump
        }
    }

    var loggedByName: String? {
        switch self {
        case .feed(let feed): return feed.loggedByName
        case .diaper(let diaper): return diaper.loggedByName
        case .pump(let pump): return pump.loggedByName
        }
    }

    @MainActor var summary: String {
        switch self {
        case .feed(let feed): return feed.timelineSummary
        case .diaper(let diaper): return diaper.timelineSummary
        case .pump(let pump): return pump.timelineSummary
        }
    }
}

// MARK: - Sheet

private enum TimelineSheet: Identifiable {
    case createFeed, createDiaper, createPump
    case editFeed(Feed), editDiaper(Diaper), editPump(Pump)

    var id: String {
        switch self {
        case .createFeed: return "create-feed"
        case .createDiaper: return "create-diaper"
        case .createPump: return "create-pump"
        case .editFeed(let feed): return "edit-feed-\(feed.id.uuidString)"
        case .editDiaper(let diaper): return "edit-diaper-\(diaper.id.uuidString)"
        case .editPump(let pump): return "edit-pump-\(pump.id.uuidString)"
        }
    }
}

// MARK: - Row

/// One timeline entry: type-tinted icon, summary + "logged by" attribution, and a
/// right column with the clock time over a live "X ago" gap. Tap to edit, swipe to delete.
struct TimelineRowView: View {
    let item: TimelineItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.event.symbolName)
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .background(item.event.tint.opacity(0.18), in: .rect(cornerRadius: 9))
                .foregroundStyle(item.event.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.summary)
                    .font(.body)
                LoggedByLabel(name: item.loggedByName)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeFormatting.clock(item.timestamp))
                    .font(.subheadline.monospacedDigit())
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("\(TimeFormatting.elapsedShort(context.date.timeIntervalSince(item.timestamp))) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.summary) at \(TimeFormatting.clock(item.timestamp))")
        .accessibilityHint("Double tap to edit")
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
