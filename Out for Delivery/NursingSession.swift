//
//  NursingSession.swift
//  Out for Delivery
//
//  The live, in-memory model behind the nursing timer (stories 8.1, 8.3, 8.4, 8.5).
//  Unlike contractions, an in-progress nursing session is NOT persisted to Core Data
//  / CloudKit: a half-finished session syncing to other caregivers would be noise, and
//  newborn mode's discipline is "create the record only on confirm" (see EditFeedView /
//  FeedService.addFeed). So the running clock lives here and is committed to a single
//  breast Feed (rounded minutes per side) when the caregiver stops.
//
//  Because a nursing session can run 20-40 minutes and the app may be backgrounded or
//  killed mid-feed, the running state is mirrored to UserDefaults on every mutation and
//  restored on launch, so reopening the app resumes the same clock.
//
//  This is a single shared session (one baby nurses at a time); it remembers which
//  baby it belongs to so the timer screen only resumes a session for the active baby.
//

import Foundation
import Observation

/// Which breast a nursing segment is on. A standalone type (not SwiftUI's `Edge`) so
/// the nursing vocabulary stays explicit. Stored only transiently — the committed Feed
/// keeps minutes per side, not a side enum.
enum NursingSide: String, CaseIterable, Hashable {
    case left
    case right

    var label: String { self == .left ? "Left" : "Right" }
    var short: String { self == .left ? "L" : "R" }
    var opposite: NursingSide { self == .left ? .right : .left }
}

@MainActor
@Observable
final class NursingSession {
    static let shared = NursingSession()

    /// The baby this running session belongs to. nil when idle.
    private(set) var babyID: UUID?
    /// The side currently counting up, or nil when paused / not yet started.
    private(set) var activeSide: NursingSide?
    /// Folded (committed) seconds per side, excluding the live segment in progress.
    private(set) var leftSeconds: TimeInterval = 0
    private(set) var rightSeconds: TimeInterval = 0
    /// When the current live segment began (nil while paused). The live portion is
    /// `now - segmentStart` and is folded into the side totals on pause / switch / stop.
    private(set) var segmentStart: Date?
    /// When this session first started — used as the feed timestamp on commit.
    private(set) var startedAt: Date?

    private let store: UserDefaults
    private let storeKey: String
    /// Injectable clock so the accumulation math is deterministically testable. In the
    /// app this is `Date.init`; tests pass a controllable closure.
    private let now: () -> Date

    private init() {
        self.store = .standard
        self.storeKey = "nursingSession.v1"
        self.now = Date.init
        restore()
    }

    /// Test seam: an isolated session with a controllable clock and a scratch store.
    init(now: @escaping () -> Date, store: UserDefaults, storeKey: String = "nursingSession.test") {
        self.now = now
        self.store = store
        self.storeKey = storeKey
        restore()
    }

    // MARK: - Derived state

    /// A side is actively counting up.
    var isRunning: Bool { activeSide != nil }

    /// There is a session worth committing (any time recorded, or one started).
    var hasContent: Bool {
        startedAt != nil && (leftSeconds + rightSeconds > 0 || segmentStart != nil)
    }

    /// Folded seconds for a side, plus the live segment when that side is active.
    func seconds(for side: NursingSide) -> TimeInterval {
        let base = side == .left ? leftSeconds : rightSeconds
        if activeSide == side, let segmentStart {
            return base + now().timeIntervalSince(segmentStart)
        }
        return base
    }

    /// Total seconds across both sides, including the live segment.
    var totalSeconds: TimeInterval { seconds(for: .left) + seconds(for: .right) }

    /// A synthetic start `Date` for a `Text(timerInterval:)` live count-up on the
    /// active side: `segmentStart` shifted back by the side's already-folded seconds, so
    /// the rendered clock reads folded + live. nil when the side isn't actively running.
    func liveStart(for side: NursingSide) -> Date? {
        guard activeSide == side, let segmentStart else { return nil }
        let base = side == .left ? leftSeconds : rightSeconds
        return segmentStart.addingTimeInterval(-base)
    }

    /// A synthetic start `Date` for a live total count-up while a side is running.
    var liveTotalStart: Date? {
        guard let segmentStart else { return nil }
        return segmentStart.addingTimeInterval(-(leftSeconds + rightSeconds))
    }

    // MARK: - Controls (stories 8.1 / 8.5)

    /// Begin (or resume) counting on `side`, binding the session to a baby on first start.
    func start(_ side: NursingSide, for babyID: UUID) {
        if startedAt == nil {
            startedAt = now()
            self.babyID = babyID
        }
        foldSegment()
        activeSide = side
        segmentStart = now()
        persist()
    }

    /// Tap behaviour for a side button: pause if it's the running side, otherwise switch
    /// to (or start) it.
    func tap(_ side: NursingSide, for babyID: UUID) {
        if activeSide == side {
            pause()
        } else {
            start(side, for: babyID)
        }
    }

    /// Stop counting but keep the recorded time (the live segment is folded in).
    func pause() {
        foldSegment()
        activeSide = nil
        segmentStart = nil
        persist()
    }

    /// Folds the live segment into its side's total and clears the segment marker.
    private func foldSegment() {
        guard let side = activeSide, let segmentStart else { return }
        let elapsed = now().timeIntervalSince(segmentStart)
        if side == .left { leftSeconds += elapsed } else { rightSeconds += elapsed }
        self.segmentStart = nil
    }

    // MARK: - Commit / reset

    /// The values to log when the caregiver stops, with each side rounded to whole
    /// minutes (0 becomes nil so a side that was barely used isn't recorded).
    struct Result {
        var leftMinutes: Int?
        var rightMinutes: Int?
        var startedAt: Date
    }

    /// Folds any live segment and returns the rounded result. Does not clear the
    /// session — call `reset()` after the feed is saved.
    func commit() -> Result {
        foldSegment()
        func minutes(_ seconds: TimeInterval) -> Int? {
            let m = Int((seconds / 60).rounded())
            return m > 0 ? m : nil
        }
        return Result(
            leftMinutes: minutes(leftSeconds),
            rightMinutes: minutes(rightSeconds),
            startedAt: startedAt ?? now()
        )
    }

    /// Clears the session back to idle (after a successful save, or to discard).
    func reset() {
        babyID = nil
        activeSide = nil
        leftSeconds = 0
        rightSeconds = 0
        segmentStart = nil
        startedAt = nil
        store.removeObject(forKey: storeKey)
    }

    // MARK: - Next-side suggestion (story 8.3)

    /// Which side to start on next: the opposite of whichever side had more time in the
    /// most recent nursing feed, so a caregiver naturally alternates. Falls back to
    /// `.left` when there's no nursing history (or the last feed used both equally).
    static func suggestedStartSide(lastNursingFeed feed: Feed?) -> NursingSide {
        guard let feed, feed.feedKind == .breast else { return .left }
        let left = feed.leftMinutes ?? 0
        let right = feed.rightMinutes ?? 0
        if left == right { return .left }
        return left > right ? .right : .left
    }

    // MARK: - Persistence (background / relaunch recovery)

    private func persist() {
        // Insert only unwrapped values: `optional as Any` would box the Optional itself,
        // which UserDefaults rejects as a non-property-list object.
        var snapshot: [String: Any] = [
            "leftSeconds": leftSeconds,
            "rightSeconds": rightSeconds
        ]
        if let babyID { snapshot["babyID"] = babyID.uuidString }
        if let activeSide { snapshot["activeSide"] = activeSide.rawValue }
        if let segmentStart { snapshot["segmentStart"] = segmentStart }
        if let startedAt { snapshot["startedAt"] = startedAt }
        store.set(snapshot, forKey: storeKey)
    }

    private func restore() {
        guard let snapshot = store.dictionary(forKey: storeKey) else { return }
        babyID = (snapshot["babyID"] as? String).flatMap(UUID.init(uuidString:))
        activeSide = (snapshot["activeSide"] as? String).flatMap(NursingSide.init(rawValue:))
        leftSeconds = snapshot["leftSeconds"] as? TimeInterval ?? 0
        rightSeconds = snapshot["rightSeconds"] as? TimeInterval ?? 0
        segmentStart = snapshot["segmentStart"] as? Date
        startedAt = snapshot["startedAt"] as? Date
    }
}
