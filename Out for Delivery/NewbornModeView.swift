//
//  NewbornModeView.swift
//  Out for Delivery
//
//  Newborn-mode home: an at-a-glance dashboard for the active baby (Epic 11). Shows
//  the feed-on-demand countdown, the most recent feed / diaper / pump and how long
//  ago each was, today's totals, and one-tap quick-log actions. Recent tiles push to
//  the per-type logs (feeds, diapers, pumps) where events are reviewed and edited.
//
//  Visual language follows the design baseline but uses native iOS 26 SwiftUI:
//  semantic tints over system materials, solid/legible cards for the medical numbers
//  (monospaced digits), and Liquid Glass reserved for the primary quick-log actions.
//

import SwiftUI
import CoreData

/// The newborn-mode tabs surfaced in the Liquid Glass bottom bar (design frames
/// 01/07). Growth is a stub until Epic 12; Family stays in the More menu for now.
private enum NewbornTab: Hashable {
    case home, timeline, growth
}

struct NewbornModeView: View {
    @State private var appState = AppState.shared
    @State private var selectedTab: NewbornTab = .home
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: true)]
    ) private var allBabies: FetchedResults<Baby>

    private var babies: [Baby] { allBabies.filter { !$0.isArchived } }
    private var activeBaby: Baby? {
        babies.first(where: { $0.id == appState.activeBabyID }) ?? babies.first
    }

    var body: some View {
        if let baby = activeBaby {
            // Native iOS 26 TabView renders the floating Liquid Glass bottom bar. Each
            // tab owns its NavigationStack so pushes (recent tiles → per-type logs) keep
            // independent back stacks. `.id(baby.id)` rebuilds the per-baby fetches when
            // the active baby changes, the way FeedSectionView scopes its fetch by id.
            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house", value: NewbornTab.home) {
                    NavigationStack {
                        BabyDashboardView(baby: baby)
                            .navigationTitle(baby.name)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { toolbarContent }
                    }
                }
                Tab("Timeline", systemImage: "list.bullet", value: NewbornTab.timeline) {
                    NavigationStack {
                        BabyTimelineView(baby: baby)
                            .toolbar { toolbarContent }
                    }
                }
                Tab("Growth", systemImage: "chart.line.uptrend.xyaxis", value: NewbornTab.growth) {
                    NavigationStack {
                        GrowthPlaceholderView()
                            .toolbar { toolbarContent }
                    }
                }
            }
            .id(baby.id)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "No baby selected",
                    systemImage: "figure.child",
                    description: Text("Add a baby to start tracking.")
                )
                .navigationTitle("Baby")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            @Bindable var appState = appState
            Menu {
                if babies.count > 1 {
                    Picker("Active Baby", selection: $appState.activeBabyID) {
                        ForEach(babies) { baby in
                            Text(baby.name).tag(Optional(baby.id))
                        }
                    }
                    Divider()
                }
                ModeMenuButtons()
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Growth tab (stub)

/// Placeholder for the Growth tab until Epic 12 (weight / length / head, trend chart)
/// lands. Keeps the bottom bar matching the design while the feature is built.
private struct GrowthPlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Growth tracking", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Weight, length, and head measurements are coming soon.")
        }
        .navigationTitle("Growth")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Dashboard for one baby

private struct BabyDashboardView: View {
    @ObservedObject var baby: Baby
    @FetchRequest private var feeds: FetchedResults<Feed>
    @FetchRequest private var diapers: FetchedResults<Diaper>
    @FetchRequest private var pumps: FetchedResults<Pump>

    @State private var sheet: LogSheet?

    private enum LogSheet: Identifiable {
        case feed, nursing, diaper, pump
        var id: Self { self }
    }

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let id = baby.id
        let newestFirst = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let predicate = NSPredicate(format: "babyID == %@", id as CVarArg)
        _feeds = FetchRequest(sortDescriptors: newestFirst, predicate: predicate)
        _diapers = FetchRequest(sortDescriptors: newestFirst, predicate: predicate)
        _pumps = FetchRequest(sortDescriptors: newestFirst, predicate: predicate)
    }

    private var unit: VolumeUnit { AppState.shared.volumeUnit }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if baby.feedReminderEnabled, baby.feedAlarmID != nil {
                    reminderCard
                }
                recentSection
                totalsCard
                quickLogSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $sheet) { which in
            switch which {
            case .feed:
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
            case .nursing:
                NursingTimerView(baby: baby)
            case .diaper:
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
            case .pump:
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
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(initial)
                .font(.title3.weight(.semibold).monospaced())
                .frame(width: 46, height: 46)
                .background(NewbornEvent.feed.tint.opacity(0.18), in: .circle)
                .foregroundStyle(NewbornEvent.feed.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(baby.name)
                    .font(.largeTitle.weight(.bold))
                Text(baby.ageDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var initial: String {
        String(baby.name.first.map(String.init) ?? "?").uppercased()
    }

    // MARK: Feed reminder countdown

    private var reminderCard: some View {
        let fire = FeedMath.reminderFireDate(lastFeed: feeds.first?.timestamp, interval: baby.feedReminderInterval)
        return NavigationLink {
            FeedDetailView(baby: baby)
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, fire.timeIntervalSince(context.date))
                let elapsed = baby.feedReminderInterval - remaining
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Next feed reminder")
                                    .font(.subheadline.weight(.semibold))
                                Text("Alerts at \(TimeFormatting.clock(fire))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(NewbornEvent.feed.tint)
                        }
                        Spacer()
                        Text(countdown(remaining))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(NewbornEvent.feed.tint)
                    }
                    ProgressView(value: min(max(elapsed, 0), baby.feedReminderInterval),
                                 total: baby.feedReminderInterval)
                        .tint(NewbornEvent.feed.tint)
                }
                .foregroundStyle(.primary)
                .padding(16)
                .background(NewbornEvent.feed.tint.opacity(0.10), in: .rect(cornerRadius: 22))
            }
        }
        .buttonStyle(.plain)
    }

    /// `h:mm:ss` while more than an hour out, otherwise `m:ss` — the at-a-glance
    /// countdown to the next reminder.
    private func countdown(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Recent tiles

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Recent")
            HStack(spacing: 9) {
                NavigationLink { FeedDetailView(baby: baby) } label: {
                    RecentTile(event: .feed, title: "Last feed",
                               timestamp: feeds.first?.timestamp, detail: feedDetail)
                }
                .buttonStyle(.plain)

                NavigationLink { DiaperListView(baby: baby) } label: {
                    RecentTile(event: .diaper, title: "Last change",
                               timestamp: diapers.first?.timestamp, detail: diaperDetail)
                }
                .buttonStyle(.plain)

                NavigationLink { PumpListView(baby: baby) } label: {
                    RecentTile(event: .pump, title: "Last pump",
                               timestamp: pumps.first?.timestamp, detail: pumpDetail)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var feedDetail: String? {
        guard let feed = feeds.first else { return nil }
        switch feed.feedKind {
        case .bottle:
            let amount = feed.volume.map { unit.formatted(fromMilliliters: $0) }
            switch (amount, feed.bottle?.label.lowercased()) {
            case let (amount?, content?): return "\(amount) · \(content)"
            case let (amount?, nil): return amount
            case let (nil, content?): return content
            case (nil, nil): return "Bottle"
            }
        case .breast:
            if let minutes = feed.nursingMinutes { return "\(minutes) min" }
            return "Nursing"
        case .unspecified:
            return nil
        }
    }

    private var diaperDetail: String? {
        diapers.first?.diaperKind.label.lowercased()
    }

    private var pumpDetail: String? {
        pumps.first?.totalVolume.map { unit.formatted(fromMilliliters: $0) }
    }

    // MARK: Daily totals

    private var totalsCard: some View {
        let calendar = Calendar.current
        let now = Date()
        let feedsToday = feeds.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }.count
        let todayDiapers = diapers.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let wet = todayDiapers.filter(\.isWet).count
        let dirty = todayDiapers.filter(\.isDirty).count
        let pumped = pumps
            .filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
            .reduce(0.0) { $0 + ($1.totalVolume ?? 0) }

        return HStack(spacing: 0) {
            totalCell("\(feedsToday)", "feeds")
            totalsDivider
            totalCell("\(wet)", "wet")
            totalsDivider
            totalCell("\(dirty)", "dirty")
            totalsDivider
            totalCell(unit.inputString(fromMilliliters: pumped), "\(unit.abbreviation) pumped")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func totalCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalsDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 28)
    }

    // MARK: Quick log

    private var quickLogSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Log")
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    quickLogButton(.feed) { sheet = .feed }
                    nursingQuickButton { sheet = .nursing }
                    quickLogButton(.diaper) { sheet = .diaper }
                    quickLogButton(.pump) { sheet = .pump }
                }
            }
        }
    }

    /// The live nursing timer entry (story 8.1). Shares the feed tint but carries a
    /// stopwatch glyph to read as "time it live" rather than "log a bottle".
    private func nursingQuickButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "stopwatch.fill")
                    .font(.title2)
                Text("Nursing")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
        .tint(NewbornEvent.feed.tint)
        .accessibilityHint("Opens the live nursing timer")
    }

    private func quickLogButton(_ event: NewbornEvent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: event.symbolName)
                    .font(.title2)
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
        .tint(event.tint)
        .accessibilityHint("Opens a new \(event.title.lowercased()) to log")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }
}

// MARK: - Recent tile

private struct RecentTile: View {
    let event: NewbornEvent
    let title: String
    let timestamp: Date?
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: event.symbolName)
                .font(.subheadline)
                .frame(width: 30, height: 30)
                .background(event.tint.opacity(0.18), in: .rect(cornerRadius: 9))
                .foregroundStyle(event.tint)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let timestamp {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(TimeFormatting.elapsedShort(context.date.timeIntervalSince(timestamp)))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(detail ?? "Not logged")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}
