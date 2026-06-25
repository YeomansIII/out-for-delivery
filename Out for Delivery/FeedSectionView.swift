//
//  FeedSectionView.swift
//  Out for Delivery
//
//  The feed-tracking portion of the newborn dashboard for one baby: a live
//  "time since last feed" readout (tap to edit the last feed), Log Bottle / Log
//  Breast actions that open a pre-typed editor (the feed is created on Save), the
//  recent-feeds list (edit / delete), and the per-baby feed-on-demand reminder controls.
//

import SwiftUI
import SwiftData

struct FeedSectionView: View {
    @Bindable var baby: Baby
    @Query private var feeds: [Feed]

    @State private var appState = AppState.shared
    @State private var sheet: FeedSheet?

    /// Which editor sheet is shown. Create mode carries no model (the feed is
    /// inserted only on Save), so presenting it never races an insert-driven
    /// re-render. Edit mode keys on `Feed.id` (our stable UUID), not the model's
    /// `persistentModelID`, which would otherwise change on save and dismiss the sheet.
    private enum FeedSheet: Identifiable {
        case create(FeedKind)
        case edit(Feed)

        var id: String {
            switch self {
            case .create(let kind): return "create-\(kind.rawValue)"
            case .edit(let feed): return "edit-\(feed.id.uuidString)"
            }
        }
    }

    /// Preset reminder intervals offered in the picker.
    private let intervalOptions: [TimeInterval] = [2, 2.5, 3, 3.5, 4].map { $0 * 3600 }

    init(baby: Baby) {
        _baby = Bindable(wrappedValue: baby)
        let id = baby.id
        _feeds = Query(
            filter: #Predicate<Feed> { $0.babyID == id },
            sort: \Feed.timestamp,
            order: .reverse
        )
    }

    private var lastFeed: Feed? { feeds.first }

    var body: some View {
        Group {
            statusSection
            logButtonSection
            unitsSection
            reminderSection
            if !feeds.isEmpty { recentSection }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .create(let kind):
                EditFeedView(creating: kind) { draft in
                    FeedService.shared.addFeed(
                        for: baby.id,
                        timestamp: draft.timestamp,
                        kind: draft.kind,
                        volume: draft.volume,
                        leftMinutes: draft.leftMinutes,
                        rightMinutes: draft.rightMinutes
                    )
                }
            case .edit(let feed):
                EditFeedView(editing: feed) { draft in
                    FeedService.shared.update(
                        feed,
                        timestamp: draft.timestamp,
                        kind: draft.kind,
                        volume: draft.volume,
                        leftMinutes: draft.leftMinutes,
                        rightMinutes: draft.rightMinutes
                    )
                }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Feeding") {
            if let last = lastFeed {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last feed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(TimeFormatting.clock(last.timestamp))
                                .font(.title3.weight(.semibold))
                        }
                        Spacer()
                        Text("\(TimeFormatting.elapsedShort(context.date.timeIntervalSince(last.timestamp))) ago")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { sheet = .edit(last) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Last feed at \(TimeFormatting.clock(last.timestamp))")
                    .accessibilityHint("Double tap to edit")
                    .accessibilityAddTraits(.isButton)
                }
            } else {
                Text("No feeds logged yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Log

    private var logButtonSection: some View {
        Section {
            HStack(spacing: 12) {
                logButton("Log Bottle", kind: .bottle)
                logButton("Log Breast", kind: .breast)
            }
            .listRowBackground(Color.clear)
        }
    }

    /// Opens the editor pre-typed to `kind` (defaulting to now). The feed is created
    /// on Save, so the type is pre-picked and entering time / volume / minutes takes
    /// the fewest taps — and nothing is inserted while the sheet is appearing.
    private func logButton(_ title: String, kind: FeedKind) -> some View {
        Button {
            sheet = .create(kind)
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("Opens a new \(kind.label.lowercased()) feed to log")
    }

    // MARK: - Units

    private var unitsSection: some View {
        @Bindable var appState = appState
        return Section("Bottle volume") {
            Picker("Unit", selection: $appState.volumeUnit) {
                ForEach(VolumeUnit.allCases, id: \.self) { unit in
                    Text(unit.label).tag(unit)
                }
            }
        }
    }

    // MARK: - Reminder settings

    private var reminderSection: some View {
        Section {
            Toggle("Feed-on-demand reminder", isOn: $baby.feedReminderEnabled)
                .onChange(of: baby.feedReminderEnabled) {
                    Task { await FeedReminderManager.shared.reschedule(for: baby) }
                }

            if baby.feedReminderEnabled {
                Picker("Remind after", selection: $baby.feedReminderInterval) {
                    ForEach(intervalOptions, id: \.self) { seconds in
                        Text(intervalLabel(seconds)).tag(seconds)
                    }
                }
                .onChange(of: baby.feedReminderInterval) {
                    Task { await FeedReminderManager.shared.reschedule(for: baby) }
                }

                if let fire = nextReminderFire {
                    HStack {
                        Text("Next reminder")
                        Spacer()
                        Text(TimeFormatting.clock(fire))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text("If no feed is logged within the interval, an alarm sounds (even on silent or in a Focus), like the Clock app's alarm. Logging a feed resets the timer.")
        }
    }

    /// The fire time of the currently-armed reminder: last feed (or now) + interval.
    private var nextReminderFire: Date? {
        guard baby.feedReminderEnabled, baby.feedAlarmID != nil else { return nil }
        return FeedMath.reminderFireDate(lastFeed: lastFeed?.timestamp, interval: baby.feedReminderInterval)
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours == hours.rounded() {
            return "\(Int(hours)) hours"
        }
        return String(format: "%.1f hours", hours)
    }

    // MARK: - Recent

    private var recentSection: some View {
        Section("Recent") {
            ForEach(Array(feeds.prefix(10).enumerated()), id: \.element.id) { offset, feed in
                FeedRowView(
                    feed: feed,
                    number: feeds.count - offset,
                    interval: interval(before: feed),
                    onEdit: { sheet = .edit(feed) },
                    onDelete: { FeedService.shared.delete(feed) }
                )
            }
        }
    }

    /// Start-to-start interval from the feed before `feed` (feeds are newest-first).
    private func interval(before feed: Feed) -> TimeInterval? {
        guard let idx = feeds.firstIndex(where: { $0.id == feed.id }), idx + 1 < feeds.count else {
            return nil
        }
        let previous = feeds[idx + 1]
        return feed.timestamp.timeIntervalSince(previous.timestamp)
    }
}
