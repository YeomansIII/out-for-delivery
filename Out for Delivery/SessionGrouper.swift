//
//  SessionGrouper.swift
//  Out for Delivery
//
//  Derives "sessions" from a chronological log of contractions.
//
//  A new session starts when:
//    1. It's the first contraction overall, OR
//    2. The gap from the previous contraction's startDate > `autoBreakSeconds`, OR
//    3. The contraction's `startsNewSession` flag is explicitly true.
//
//  Sessions are not persisted — they are recomputed every time the log changes.
//

import Foundation

enum SessionGrouper {
    /// Auto session break threshold. Hardcoded for now.
    static let autoBreakSeconds: TimeInterval = 2 * 60 * 60
    /// Same threshold reused to decide whether the latest session is still "current."
    static let currentSessionStalenessSeconds: TimeInterval = 2 * 60 * 60

    /// Groups a chronologically-sorted (ascending by start) array of contractions into sessions.
    /// Each inner array is one session, also ascending by start. Returned outer array is oldest session first.
    static func sessions(from chronological: [Contraction]) -> [[Contraction]] {
        guard !chronological.isEmpty else { return [] }

        var groups: [[Contraction]] = []
        var current: [Contraction] = []

        for c in chronological {
            if let prev = current.last {
                let gap = c.startDate.timeIntervalSince(prev.startDate)
                let breaks = c.startsNewSession || gap > autoBreakSeconds
                if breaks {
                    groups.append(current)
                    current = [c]
                } else {
                    current.append(c)
                }
            } else {
                current = [c]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// Returns the latest session as the "current" one, scoped by recency.
    /// If any contraction is in progress, the latest session is always current.
    /// Otherwise, the latest session is only current if its newest contraction started within
    /// `currentSessionStalenessSeconds` of `now`. Returns `[]` otherwise — signalling
    /// "between sessions, awaiting a fresh start."
    static func currentSession(from chronological: [Contraction], now: Date = Date()) -> [Contraction] {
        let groups = sessions(from: chronological)
        guard let latest = groups.last else { return [] }

        let hasOpen = latest.contains(where: { $0.isInProgress })
        if hasOpen { return latest }

        guard let mostRecentStart = latest.last?.startDate else { return [] }
        if now.timeIntervalSince(mostRecentStart) <= currentSessionStalenessSeconds {
            return latest
        }
        return []
    }

    /// True when the given contraction begins a session (auto or manual) within the supplied log.
    static func isSessionStart(_ contraction: Contraction, in chronological: [Contraction]) -> Bool {
        let groups = sessions(from: chronological)
        return groups.contains { $0.first?.id == contraction.id }
    }

    /// True when the contraction begins a session *only* because the user flagged it
    /// (i.e. the gap rule alone wouldn't have started a session here). Used to decide
    /// whether the swipe action removes the manual marker or is a no-op.
    static func isManualSessionStart(_ contraction: Contraction, in chronological: [Contraction]) -> Bool {
        guard contraction.startsNewSession else { return false }
        guard let idx = chronological.firstIndex(where: { $0.id == contraction.id }) else { return false }
        guard idx > 0 else { return false } // The very first overall contraction is always a session start, manual flag is redundant.
        let prev = chronological[idx - 1]
        let gap = contraction.startDate.timeIntervalSince(prev.startDate)
        // Manual matters only when the gap rule wouldn't have already started a session.
        return gap <= autoBreakSeconds
    }
}
