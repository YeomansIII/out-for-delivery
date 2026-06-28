//
//  CSVImporter.swift
//  Out for Delivery
//
//  Generic CSV import framework. A picked file is parsed once, its header is
//  sniffed against the registered `CSVImportable` formats, and the first match
//  imports the rows through the owning service (preserving the single-context
//  discipline and de-duplicating so re-importing the same file is idempotent).
//
//  Today two formats ship: contractions (whose export already existed) and feeds
//  (a new symmetric export/import). Pump and diaper formats slot in here when
//  Epics 9/10 build those models — add a type and append it to `CSVImport.formats`.
//

import Foundation

/// Extra information an import may need beyond the file itself (e.g. which baby
/// feeds belong to). Formats that don't need it simply ignore the fields.
struct CSVImportContext {
    var activeBabyID: UUID?
}

/// The outcome of an import, surfaced to the caregiver.
struct CSVImportSummary {
    var formatName: String
    var imported: Int = 0
    var duplicates: Int = 0
    var skipped: Int = 0
    /// Optional explanation when nothing (or not everything) could be imported.
    var note: String?

    /// A short human summary, e.g. "Imported 42 contractions (3 duplicates skipped)."
    var message: String {
        if let note, imported == 0 { return note }
        var parts = ["Imported \(imported) \(formatName.lowercased())"]
        var extras: [String] = []
        if duplicates > 0 { extras.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s") skipped") }
        if skipped > 0 { extras.append("\(skipped) unreadable row\(skipped == 1 ? "" : "s") skipped") }
        if !extras.isEmpty { parts.append("(\(extras.joined(separator: ", ")))") }
        return parts.joined(separator: " ") + "."
    }
}

enum CSVImportError: LocalizedError {
    case unreadable
    case empty
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That file could not be read."
        case .empty: return "That file has no data to import."
        case .unrecognizedFormat: return "That CSV is not a tracking history this app recognizes."
        }
    }
}

/// A CSV shape the app can recognize and import.
protocol CSVImportable {
    /// Human name of what this format imports, e.g. "Contractions".
    static var displayName: String { get }
    /// Header sniff: true when a parsed header is this format.
    static func matches(header: [String]) -> Bool
    /// Imports the header-keyed rows through the owning service, returning a summary.
    @MainActor static func importRows(_ rows: [[String: String]], context: CSVImportContext) -> CSVImportSummary
}

enum CSVImport {
    /// Recognized formats, in detection order. Append new formats here.
    static let formats: [any CSVImportable.Type] = [
        ContractionCSVFormat.self,
        FeedCSVFormat.self,
    ]

    /// Parses a picked CSV file, sniffs its format, and imports it. Throws when the
    /// file can't be read, is empty, or matches no known format.
    @MainActor
    static func importFile(at url: URL, context: CSVImportContext) throws -> CSVImportSummary {
        // Files picked outside the sandbox need security-scoped access.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            throw CSVImportError.unreadable
        }
        guard let parsed = CSV.parse(text) else { throw CSVImportError.empty }
        guard let format = formats.first(where: { $0.matches(header: parsed.header) }) else {
            throw CSVImportError.unrecognizedFormat
        }
        let rows = parsed.rows.map { CSV.keyed(header: parsed.header, row: $0) }
        return format.importRows(rows, context: context)
    }
}

// MARK: - Records handed to the services

struct ContractionImport {
    let start: Date
    let end: Date?
}

struct FeedImport {
    let timestamp: Date
    let kind: FeedKind
    let volume: Double?
    let leftMinutes: Int?
    let rightMinutes: Int?
    let note: String?
}

// MARK: - Contraction format

/// Imports the app's contraction export. Authoritative columns are `start_iso8601`
/// and `end_iso8601`; everything else is derived and ignored on import. Sessions are
/// re-derived by SessionGrouper from the imported start times, so `startsNewSession`
/// is not part of the file.
enum ContractionCSVFormat: CSVImportable {
    static let displayName = "Contractions"

    static func matches(header: [String]) -> Bool {
        header.contains("start_iso8601")
    }

    /// Pure decode of header-keyed rows into import records. No side effects, so the
    /// round trip is unit-testable without a store.
    static func decode(_ rows: [[String: String]]) -> (records: [ContractionImport], skipped: Int) {
        var records: [ContractionImport] = []
        var skipped = 0
        for row in rows {
            guard let start = CSVDate.date(from: row["start_iso8601"] ?? "") else {
                skipped += 1
                continue
            }
            records.append(ContractionImport(start: start, end: CSVDate.date(from: row["end_iso8601"] ?? "")))
        }
        return (records, skipped)
    }

    @MainActor
    static func importRows(_ rows: [[String: String]], context: CSVImportContext) -> CSVImportSummary {
        let decoded = decode(rows)
        let result = ContractionService.shared.importContractions(decoded.records)
        return CSVImportSummary(formatName: displayName,
                                imported: result.imported,
                                duplicates: result.duplicates,
                                skipped: decoded.skipped)
    }
}

// MARK: - Feed format

/// Imports the feed export into the active baby. Requires an active baby; without
/// one the rows are skipped with an explanatory note (feeds are baby-scoped).
enum FeedCSVFormat: CSVImportable {
    static let displayName = "Feeds"

    static func matches(header: [String]) -> Bool {
        header.contains("timestamp_iso8601") && header.contains("kind")
    }

    /// Pure decode of header-keyed rows into import records. No side effects, so the
    /// round trip is unit-testable without a store.
    static func decode(_ rows: [[String: String]]) -> (records: [FeedImport], skipped: Int) {
        var records: [FeedImport] = []
        var skipped = 0
        for row in rows {
            guard let timestamp = CSVDate.date(from: row["timestamp_iso8601"] ?? "") else {
                skipped += 1
                continue
            }
            let rawKind = (row["kind"] ?? "").trimmingCharacters(in: .whitespaces)
            let kind = FeedKind(rawValue: rawKind) ?? .unspecified
            let note = (row["note"]).flatMap { $0.isEmpty ? nil : $0 }
            records.append(FeedImport(
                timestamp: timestamp,
                kind: kind,
                volume: parseDouble(row["volume_ml"]),
                leftMinutes: parseInt(row["left_minutes"]),
                rightMinutes: parseInt(row["right_minutes"]),
                note: note
            ))
        }
        return (records, skipped)
    }

    @MainActor
    static func importRows(_ rows: [[String: String]], context: CSVImportContext) -> CSVImportSummary {
        guard let babyID = context.activeBabyID else {
            return CSVImportSummary(formatName: displayName,
                                    skipped: rows.count,
                                    note: "Select a baby before importing feeds.")
        }
        let decoded = decode(rows)
        let result = FeedService.shared.importFeeds(for: babyID, records: decoded.records)
        return CSVImportSummary(formatName: displayName,
                                imported: result.imported,
                                duplicates: result.duplicates,
                                skipped: decoded.skipped)
    }
}

// MARK: - Field parsing helpers

private func parseDouble(_ value: String?) -> Double? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
    return Double(trimmed)
}

private func parseInt(_ value: String?) -> Int? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
    return Int(trimmed)
}
