//
//  CSV.swift
//  Out for Delivery
//
//  Low-level CSV codec shared by every import/export format. Handles RFC 4180
//  quoting (commas, quotes, and newlines inside quoted fields) so free-text
//  columns like a feed note round-trip safely. Date columns use a single shared
//  ISO 8601 representation (`CSVDate`) so exports and imports agree exactly.
//

import Foundation

enum CSV {
    /// Serializes a header plus rows into a CSV string (trailing newline included).
    static func serialize(header: [String], rows: [[String]]) -> String {
        var lines = [encodeRow(header)]
        lines.append(contentsOf: rows.map(encodeRow))
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses CSV text into its header and remaining rows. Returns nil when there
    /// isn't even a header line. Rows are returned as field arrays aligned to the
    /// order they appear (callers zip them against the header).
    static func parse(_ text: String) -> (header: [String], rows: [[String]])? {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        // Iterate over unicode scalars, not Characters: Swift folds "\r\n" into a
        // single Character grapheme, which would hide CRLF record terminators.
        let scalars = Array(text.unicodeScalars)
        var i = 0

        func endField() { record.append(field); field = "" }
        func endRecord() { endField(); records.append(record); record = [] }

        while i < scalars.count {
            let ch = scalars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                } else {
                    field.unicodeScalars.append(ch)
                    i += 1
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                    i += 1
                case ",":
                    endField()
                    i += 1
                case "\n":
                    endRecord()
                    i += 1
                case "\r":
                    // Treat CRLF as a single record terminator.
                    if i + 1 < scalars.count, scalars[i + 1] == "\n" {
                        endRecord()
                        i += 2
                    } else {
                        endRecord()
                        i += 1
                    }
                default:
                    field.unicodeScalars.append(ch)
                    i += 1
                }
            }
        }
        // Flush any trailing field/record when the file has no final newline.
        if !field.isEmpty || !record.isEmpty { endRecord() }

        // Drop blank records (e.g. produced by a trailing newline).
        records = records.filter { !($0.count == 1 && $0[0].isEmpty) }

        guard let header = records.first else { return nil }
        return (header, Array(records.dropFirst()))
    }

    /// Zips a row's fields against the header into a name-keyed dictionary.
    /// Missing trailing fields are simply absent (callers treat absent as empty).
    static func keyed(header: [String], row: [String]) -> [String: String] {
        Dictionary(zip(header, row), uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Field encoding

    private static func encodeRow(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The single ISO 8601 date representation every CSV format shares. Export writes
/// fractional seconds; import accepts dates with or without them so files edited
/// by hand or produced by other tools still load.
enum CSVDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return withFraction.date(from: trimmed) ?? withoutFraction.date(from: trimmed)
    }
}
