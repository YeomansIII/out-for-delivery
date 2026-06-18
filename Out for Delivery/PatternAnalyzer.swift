//
//  PatternAnalyzer.swift
//  Out for Delivery
//
//  Passive 5-1-1 (or selected) readout. Recomputed on every log change.
//

import Foundation

struct PatternRule: Equatable {
    /// Max start-to-start interval, seconds.
    var maxIntervalSeconds: TimeInterval
    /// Min contraction duration, seconds.
    var minDurationSeconds: TimeInterval
    /// Sustain window — the pattern must have held this long.
    var sustainWindowSeconds: TimeInterval

    static let fiveOneOne = PatternRule(
        maxIntervalSeconds: 5 * 60,
        minDurationSeconds: 1 * 60,
        sustainWindowSeconds: 60 * 60
    )
}

struct PatternResult: Equatable {
    var avgInterval: TimeInterval?
    var avgDuration: TimeInterval?
    var met: Bool
}

enum PatternAnalyzer {
    static func evaluate(all: [Contraction], rule: PatternRule = .fiveOneOne, now: Date = Date()) -> PatternResult {
        // Sorted ascending by start. Only completed rows contribute to averages.
        let completed = all.filter { $0.endDate != nil }
        guard completed.count >= 2 else {
            return PatternResult(avgInterval: nil, avgDuration: nil, met: false)
        }

        // Window: rule.sustainWindowSeconds trailing.
        let cutoff = now.addingTimeInterval(-rule.sustainWindowSeconds)
        let windowed = completed.filter { $0.startDate >= cutoff }
        guard windowed.count >= 2 else {
            return PatternResult(
                avgInterval: avgInterval(of: completed.suffix(6).map { $0 }),
                avgDuration: avgDuration(of: completed.suffix(6).map { $0 }),
                met: false
            )
        }

        let avgInt = avgInterval(of: windowed)
        let avgDur = avgDuration(of: windowed)

        let intervalsOK = startToStartIntervals(of: windowed)
            .allSatisfy { $0 <= rule.maxIntervalSeconds }
        let durationsOK = windowed
            .compactMap { $0.duration }
            .allSatisfy { $0 >= rule.minDurationSeconds }
        // The window itself must span ≥ sustainWindowSeconds.
        let span = (windowed.last?.startDate ?? now).timeIntervalSince(windowed.first?.startDate ?? now)
        let sustained = span >= rule.sustainWindowSeconds

        return PatternResult(
            avgInterval: avgInt,
            avgDuration: avgDur,
            met: intervalsOK && durationsOK && sustained
        )
    }

    private static func startToStartIntervals(of contractions: [Contraction]) -> [TimeInterval] {
        guard contractions.count >= 2 else { return [] }
        return zip(contractions.dropFirst(), contractions.dropLast()).map { later, earlier in
            later.startDate.timeIntervalSince(earlier.startDate)
        }
    }

    private static func avgInterval(of contractions: [Contraction]) -> TimeInterval? {
        let intervals = startToStartIntervals(of: contractions)
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    private static func avgDuration(of contractions: [Contraction]) -> TimeInterval? {
        let durations = contractions.compactMap { $0.duration }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }
}
