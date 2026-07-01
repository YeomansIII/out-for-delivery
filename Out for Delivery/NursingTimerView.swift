//
//  NursingTimerView.swift
//  Out for Delivery
//
//  The live nursing timer (design frames 10 "ready to start" and 03 "running"),
//  covering stories 8.1 (one-tap start/stop), 8.3 (next-side suggestion), 8.4 (haptics)
//  and 8.5 (live count-up). Two large side buttons drive a `NursingSession`; tapping a
//  side starts/switches to it, tapping the running side pauses. On Stop & save the
//  session is committed to a single breast Feed via the normal FeedService path, so the
//  result is reviewed and edited from the log/timeline like any other feed.
//
//  This is an in-app screen only: no Live Activity / Lock Screen surface (the contraction
//  timer is the one alarmless-but-live exception; nursing stays in-app and calm).
//

import SwiftUI

struct NursingTimerView: View {
    let baby: Baby

    @Environment(\.dismiss) private var dismiss
    @State private var session = NursingSession.shared

    @State private var note: String
    @State private var startedAt: Date
    /// Flipped on save to drive the success haptic (story 8.4).
    @State private var didSave = false

    /// The side to nudge the caregiver to start on, when the session hasn't begun.
    private let suggested: NursingSide

    init(baby: Baby) {
        self.baby = baby
        let lastNursing = FeedService.shared.feeds(for: baby.id)
            .last { $0.feedKind == .breast }
        self.suggested = NursingSession.suggestedStartSide(lastNursingFeed: lastNursing)
        _note = State(initialValue: "")
        _startedAt = State(initialValue: NursingSession.shared.startedAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    totalReadout
                    sideButtons
                    if session.hasContent {
                        details
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nursing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Haptic on every start / switch / pause, and on save.
        .sensoryFeedback(.impact, trigger: session.activeSide)
        .sensoryFeedback(.success, trigger: didSave)
        .onChange(of: session.startedAt) { _, new in
            if let new { startedAt = new }
        }
    }

    // MARK: Total

    private var totalReadout: some View {
        VStack(spacing: 2) {
            Group {
                if let start = session.liveTotalStart {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                } else {
                    Text(TimeFormatting.mmss(session.totalSeconds))
                }
            }
            .font(.system(size: 56, weight: .semibold).monospacedDigit())
            .contentTransition(.numericText())

            Text(session.isRunning ? "Nursing now" : (session.hasContent ? "Paused" : "Ready to start"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: Side buttons

    private var sideButtons: some View {
        HStack(spacing: 14) {
            sideButton(.left)
            sideButton(.right)
        }
    }

    private func sideButton(_ side: NursingSide) -> some View {
        let isActive = session.activeSide == side
        // Highlight the suggested side only before the session has any content.
        let isSuggested = !session.hasContent && side == suggested
        return Button {
            session.tap(side, for: baby.id)
        } label: {
            VStack(spacing: 10) {
                Text(side.label)
                    .font(.headline)

                Group {
                    if let start = session.liveStart(for: side) {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    } else {
                        Text(TimeFormatting.mmss(session.seconds(for: side)))
                    }
                }
                .font(.system(size: 34, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())

                Text(isActive ? "Tap to pause" : (session.hasContent ? "Tap to switch" : "Tap to start"))
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.white.opacity(0.85) : .secondary)
                if isSuggested {
                    Text("Suggested")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(NewbornEvent.feed.tint)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .foregroundStyle(isActive ? .white : .primary)
            .background(
                isActive ? AnyShapeStyle(NewbornEvent.feed.tint)
                         : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: .rect(cornerRadius: 22)
            )
            .overlay {
                if isSuggested {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(NewbornEvent.feed.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: session.activeSide)
        .accessibilityLabel("\(side.label) breast")
        .accessibilityValue(TimeFormatting.compact(session.seconds(for: side)))
        .accessibilityHint(isActive ? "Pauses this side" : "Starts timing this side")
    }

    // MARK: Details (time + note)

    private var details: some View {
        VStack(spacing: 16) {
            DatePicker(
                "Started at",
                selection: $startedAt,
                in: ...Date(),
                displayedComponents: [.hourAndMinute]
            )
            .font(.subheadline)

            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    // MARK: Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button {
                save()
            } label: {
                Text("Stop & save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(NewbornEvent.feed.tint)
            .controlSize(.large)
            .disabled(!session.hasContent)

            if session.hasContent {
                Button("Discard", role: .destructive) {
                    session.reset()
                    dismiss()
                }
                .font(.subheadline)
            }

            if let attribution {
                Text(attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var attribution: String? {
        guard let name = CurrentUserIdentity.shared.currentLoggedByName, !name.isEmpty else { return nil }
        return "Logging by \(name)"
    }

    private func save() {
        let result = session.commit()
        FeedService.shared.addFeed(
            for: baby.id,
            timestamp: startedAt,
            kind: .breast,
            leftMinutes: result.leftMinutes,
            rightMinutes: result.rightMinutes,
            note: note.isEmpty ? nil : note
        )
        session.reset()
        didSave.toggle()
        dismiss()
    }
}
