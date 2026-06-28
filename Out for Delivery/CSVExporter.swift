//
//  CSVExporter.swift
//  Out for Delivery
//
//  CSV exports, built on the shared `CSV` codec so they round-trip exactly with
//  the importers in CSVImporter.swift. The contraction format and filename are
//  unchanged from the original export so previously shared files still import.
//

import Foundation

enum CSVExporter {
    /// Generates a CSV file at a temp URL containing all contractions, oldest first.
    /// Filename format: `contractions-YYYYMMDD-HHmm.csv`.
    ///
    /// Authoritative round-trip columns are `start_iso8601` and `end_iso8601`; the
    /// derived columns (index, durations, intervals) are for human/spreadsheet use
    /// and are recomputed on import.
    static func makeCSV(contractions: [Contraction], now: Date = Date()) -> URL? {
        let sorted = contractions.sorted { $0.startDate < $1.startDate }

        let header = ["index", "start_iso8601", "end_iso8601", "duration_seconds",
                      "interval_since_prev_start_seconds", "duration_mmss", "interval_mmss"]

        var rows: [[String]] = []
        for (i, c) in sorted.enumerated() {
            let startISO = CSVDate.string(from: c.startDate)
            let endISO = c.endDate.map { CSVDate.string(from: $0) } ?? ""
            let durSec = c.duration.map { String(Int($0.rounded())) } ?? ""
            let interval: TimeInterval? = i == 0 ? nil : c.startDate.timeIntervalSince(sorted[i - 1].startDate)
            let intervalSec = interval.map { String(Int($0.rounded())) } ?? ""
            let durMMSS = c.duration.map { TimeFormatting.mmss($0) } ?? ""
            let intervalMMSS = interval.map { TimeFormatting.mmss($0) } ?? ""

            rows.append([String(i + 1), startISO, endISO,
                         durSec, intervalSec, durMMSS, intervalMMSS])
        }

        return write(CSV.serialize(header: header, rows: rows), baseName: "contractions", now: now)
    }

    /// Generates a CSV file containing one baby's feeds, oldest first.
    /// Filename format: `feeds-YYYYMMDD-HHmm.csv`.
    ///
    /// Authoritative round-trip columns are `timestamp_iso8601`, `kind`, `volume_ml`,
    /// `left_minutes`, `right_minutes`, and `note`. Feeds import scoped to the active
    /// baby, so the baby identity itself is not part of the file.
    static func makeFeedCSV(feeds: [Feed], now: Date = Date()) -> URL? {
        let sorted = feeds.sorted { $0.timestamp < $1.timestamp }

        let header = ["index", "timestamp_iso8601", "kind", "volume_ml",
                      "left_minutes", "right_minutes", "note"]

        var rows: [[String]] = []
        for (i, f) in sorted.enumerated() {
            rows.append([
                String(i + 1),
                CSVDate.string(from: f.timestamp),
                f.feedKind.rawValue,
                f.volume.map { String(Int($0.rounded())) } ?? "",
                f.leftMinutes.map(String.init) ?? "",
                f.rightMinutes.map(String.init) ?? "",
                f.note ?? ""
            ])
        }

        return write(CSV.serialize(header: header, rows: rows), baseName: "feeds", now: now)
    }

    // MARK: - File writing

    /// Writes CSV text to a timestamped temp file, returning its URL (nil on failure).
    private static func write(_ csv: String, baseName: String, now: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.timeZone = .current
        let filename = "\(baseName)-\(formatter.string(from: now)).csv"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
