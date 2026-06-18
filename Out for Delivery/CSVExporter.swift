//
//  CSVExporter.swift
//  Out for Delivery
//

import Foundation

enum CSVExporter {
    /// Generates a CSV file at a temp URL containing all contractions, oldest first.
    /// Filename format: `contractions-YYYYMMDD-HHmm.csv`.
    static func makeCSV(contractions: [Contraction], now: Date = Date()) -> URL? {
        let sorted = contractions.sorted { $0.startDate < $1.startDate }

        let header = "index,start_iso8601,end_iso8601,duration_seconds,interval_since_prev_start_seconds,duration_mmss,interval_mmss"
        var lines: [String] = [header]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = TimeZone.current

        for (i, c) in sorted.enumerated() {
            let index = i + 1
            let startISO = iso.string(from: c.startDate)
            let endISO = c.endDate.map { iso.string(from: $0) } ?? ""
            let durSec = c.duration.map { String(Int($0.rounded())) } ?? ""
            let interval: TimeInterval? = i == 0 ? nil : c.startDate.timeIntervalSince(sorted[i - 1].startDate)
            let intervalSec = interval.map { String(Int($0.rounded())) } ?? ""
            let durMMSS = c.duration.map { TimeFormatting.mmss($0) } ?? ""
            let intervalMMSS = interval.map { TimeFormatting.mmss($0) } ?? ""

            lines.append([
                String(index), startISO, endISO,
                durSec, intervalSec, durMMSS, intervalMMSS
            ].joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n") + "\n"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.timeZone = TimeZone.current
        let filename = "contractions-\(formatter.string(from: now)).csv"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

}
