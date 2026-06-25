//
//  TimeFormatting.swift
//  Out for Delivery
//

import Foundation

enum TimeFormatting {
    /// `mm:ss` for durations and intervals.
    static func mmss(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Compact human-readable (`4m 10s`).
    static func compact(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let m = total / 60
        let s = total % 60
        if m == 0 { return "\(s)s" }
        if s == 0 { return "\(m)m" }
        return "\(m)m \(s)s"
    }

    /// `2:14 PM` clock time.
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Human elapsed gap like `45m`, `1h 23m`, `2d 3h` — for "time since last feed".
    static func elapsedShort(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded())
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours < 24 { return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m" }
        let days = hours / 24
        let hrs = hours % 24
        return hrs == 0 ? "\(days)d" : "\(days)d \(hrs)h"
    }
}
