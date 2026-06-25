//
//  ContentView.swift
//  Out for Delivery
//

import SwiftUI
import SwiftData
import ActivityKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Contraction.startDate, order: .reverse) private var contractionsNewestFirst: [Contraction]

    @State private var service = ContractionService.shared

    @AppStorage("hasSeenDisclaimer") private var hasSeenDisclaimer = false
    @AppStorage("liveActivityHidden") private var liveActivityHidden = false

    @State private var showDisclaimer = false
    @State private var showInfo = false
    @State private var showClearAllConfirm = false
    @State private var showExpiredBanner = false
    @State private var editingContraction: Contraction?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                StatusHeaderView(snapshot: service.snapshot)
                    .padding(.horizontal)

                if service.snapshot.avgInterval != nil || service.snapshot.avgDuration != nil {
                    AverageStatsView(snapshot: service.snapshot)
                        .padding(.horizontal)
                }

                if showExpiredBanner {
                    expiredBanner
                        .padding(.horizontal)
                }

                PrimaryControlView(
                    snapshot: service.snapshot,
                    onStart: { service.start(); haptic(.start) },
                    onStop: { service.stop(); haptic(.stop) },
                    onCancel: { service.cancelInProgress(); haptic(.cancel) }
                )
                .padding(.horizontal)

                logList
            }
            .padding(.top, 8)
            .navigationTitle("Out for Delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showDisclaimer) {
                DisclaimerView { hasSeenDisclaimer = true }
            }
            .sheet(isPresented: $showInfo) {
                InfoView()
            }
            .sheet(item: $editingContraction) { c in
                EditContractionView(contraction: c) { newStart, newEnd in
                    service.update(c, startDate: newStart, endDate: newEnd)
                    haptic(.stop)
                }
            }
            .confirmationDialog(
                "Clear all contractions?",
                isPresented: $showClearAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear all", role: .destructive) {
                    service.clearAll()
                    haptic(.cancel)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the entire log on this device and across iCloud.")
            }
            .task {
                service.refresh()
                evaluateLiveActivityState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    service.refresh()
                    evaluateLiveActivityState()
                }
            }
            .onAppear {
                if !hasSeenDisclaimer { showDisclaimer = true }
            }
        }
    }

    // MARK: - Log list

    @ViewBuilder
    private var logList: some View {
        if contractionsNewestFirst.isEmpty {
            ContentUnavailableView(
                "Order placed",
                systemImage: "shippingbox",
                description: Text("Tap Start when a contraction begins.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(sessionsNewestFirst.enumerated()), id: \.offset) { sessionIndex, session in
                    Section {
                        ForEach(session) { c in
                            ContractionRowView(
                                contraction: c,
                                number: number(for: c, in: session),
                                interval: interval(for: c, in: session),
                                canToggleSessionStart: canToggleSessionStart(c),
                                isManualSessionStart: SessionGrouper.isManualSessionStart(c, in: chronological),
                                onToggleSessionStart: { service.toggleSessionBoundary(c) },
                                onEdit: { editingContraction = c },
                                onDelete: { service.delete(c); haptic(.cancel) }
                            )
                        }
                    } header: {
                        sessionHeader(for: session, sessionsFromNewest: sessionIndex)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func sessionHeader(for session: [Contraction], sessionsFromNewest: Int) -> some View {
        let label: String = {
            if sessionsFromNewest == 0 { return "Current session" }
            if sessionsFromNewest == 1 { return "Previous session" }
            return "Session \(sessionsNewestFirst.count - sessionsFromNewest)"
        }()
        let start = session.first?.startDate
        return HStack {
            Text(label)
            Spacer()
            if let start {
                Text(TimeFormatting.clock(start))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .textCase(nil)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let url = csvURL {
                ShareLink(item: url) {
                    Label("Export tracking history", systemImage: "square.and.arrow.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ModeMenuButtons()
                Divider()
                Button {
                    Task {
                        liveActivityHidden.toggle()
                        await syncLiveActivity()
                    }
                } label: {
                    Label(
                        liveActivityHidden ? "Show on Lock Screen" : "Hide from Lock Screen",
                        systemImage: liveActivityHidden ? "lock.open" : "lock.slash"
                    )
                }
                Button(role: .destructive) {
                    showClearAllConfirm = true
                } label: {
                    Label("Clear all", systemImage: "trash")
                }
                Button {
                    showInfo = true
                } label: {
                    Label("Info & disclaimer", systemImage: "info.circle")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Expired Live Activity banner

    private var expiredBanner: some View {
        Button {
            Task {
                showExpiredBanner = false
                await LiveActivityManager.shared.startOrUpdate(with: service.snapshot)
            }
        } label: {
            HStack {
                Image(systemName: "exclamationmark.bubble")
                Text("Live Activity expired — tap to restart")
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Helpers

    private var csvURL: URL? {
        let all = service.allContractions()
        return all.isEmpty ? nil : CSVExporter.makeCSV(contractions: all)
    }

    private var chronological: [Contraction] {
        contractionsNewestFirst.reversed()
    }

    private var sessionsNewestFirst: [[Contraction]] {
        // SessionGrouper returns oldest-first chronologically; flip both axes for display.
        let oldestFirst = SessionGrouper.sessions(from: chronological)
        return oldestFirst.reversed().map { Array($0.reversed()) }
    }

    private func number(for c: Contraction, in session: [Contraction]) -> Int {
        // Session-local index: oldest in the session = 1.
        // `session` here is newest-first; convert.
        guard let idxFromNewest = session.firstIndex(where: { $0.id == c.id }) else { return 0 }
        return session.count - idxFromNewest
    }

    private func interval(for c: Contraction, in session: [Contraction]) -> TimeInterval? {
        // The previous contraction *within the same session* (chronologically earlier).
        guard let idxFromNewest = session.firstIndex(where: { $0.id == c.id }) else { return nil }
        let previousNewerIndex = idxFromNewest + 1
        guard previousNewerIndex < session.count else { return nil }
        let previous = session[previousNewerIndex]
        return c.startDate.timeIntervalSince(previous.startDate)
    }

    private func canToggleSessionStart(_ c: Contraction) -> Bool {
        // In-progress contraction always belongs to the latest session — disable the swipe.
        if c.isInProgress { return false }
        // The very first overall contraction is implicitly a session start; manual flag is redundant.
        let chrono = chronological
        guard let idx = chrono.firstIndex(where: { $0.id == c.id }) else { return false }
        return idx > 0
    }

    // MARK: - Live Activity foreground re-request

    private func evaluateLiveActivityState() {
        Task {
            await syncLiveActivity()
            showExpiredBanner = !liveActivityHidden
                && LiveActivityManager.shared.needsRestart(snapshot: service.snapshot)
        }
    }

    private func syncLiveActivity() async {
        if liveActivityHidden {
            await LiveActivityManager.shared.hide()
        } else if service.snapshot.count > 0 {
            await LiveActivityManager.shared.startOrUpdate(with: service.snapshot)
        }
    }

    // MARK: - Haptics

    private enum HapticKind { case start, stop, cancel }

    private func haptic(_ kind: HapticKind) {
        #if canImport(UIKit)
        let generator: UIImpactFeedbackGenerator
        switch kind {
        case .start: generator = UIImpactFeedbackGenerator(style: .medium)
        case .stop: generator = UIImpactFeedbackGenerator(style: .heavy)
        case .cancel: generator = UIImpactFeedbackGenerator(style: .light)
        }
        generator.impactOccurred()
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Contraction.self, inMemory: true)
}
