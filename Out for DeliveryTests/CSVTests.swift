//
//  CSVTests.swift
//  Out for DeliveryTests
//
//  Covers the generic CSV framework: the low-level codec (quoting, CRLF), the
//  shared ISO date representation, format detection, and full export -> parse ->
//  decode round trips for contractions and feeds. Round trips use the pure
//  `decode` step (no store) and the in-memory preview Core Data stack.
//

import Testing
import Foundation
import CoreData
@testable import Out_for_Delivery

struct CSVCodecTests {
    @Test func serializeParseRoundTripsPlainFields() {
        let header = ["a", "b", "c"]
        let rows = [["1", "2", "3"], ["4", "5", "6"]]
        let parsed = CSV.parse(CSV.serialize(header: header, rows: rows))
        #expect(parsed?.header == header)
        #expect(parsed?.rows == rows)
    }

    @Test func quotingRoundTripsCommasQuotesAndNewlines() {
        let header = ["note", "value"]
        let rows = [
            ["has, comma", "1"],
            ["has \"quote\"", "2"],
            ["has\nnewline", "3"],
        ]
        let parsed = CSV.parse(CSV.serialize(header: header, rows: rows))
        #expect(parsed?.rows == rows)
    }

    @Test func parseHandlesCRLFAndTrailingNewline() {
        let parsed = CSV.parse("a,b\r\n1,2\r\n")
        #expect(parsed?.header == ["a", "b"])
        #expect(parsed?.rows == [["1", "2"]])
    }

    @Test func parseReturnsNilForEmptyText() {
        #expect(CSV.parse("") == nil)
    }

    @Test func keyedAlignsFieldsToHeader() {
        let keyed = CSV.keyed(header: ["x", "y", "z"], row: ["1", "2", "3"])
        #expect(keyed == ["x": "1", "y": "2", "z": "3"])
    }
}

struct CSVDateTests {
    @Test func roundTripsToSubSecond() {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000.25)
        let back = CSVDate.date(from: CSVDate.string(from: date))
        #expect(back != nil)
        #expect(abs((back ?? .distantPast).timeIntervalSinceReferenceDate - date.timeIntervalSinceReferenceDate) < 0.01)
    }

    @Test func parsesWithoutFractionalSeconds() {
        #expect(CSVDate.date(from: "2026-06-25T08:30:00Z") != nil)
    }

    @Test func parsesEmptyOrBlankAsNil() {
        #expect(CSVDate.date(from: "") == nil)
        #expect(CSVDate.date(from: "   ") == nil)
    }
}

struct CSVFormatDetectionTests {
    private let contractionHeader = ["index", "start_iso8601", "end_iso8601", "duration_seconds",
                                     "interval_since_prev_start_seconds", "duration_mmss", "interval_mmss"]
    private let feedHeader = ["index", "timestamp_iso8601", "kind", "volume_ml",
                             "left_minutes", "right_minutes", "note"]

    @Test func contractionFormatMatchesOnlyItsHeader() {
        #expect(ContractionCSVFormat.matches(header: contractionHeader))
        #expect(!ContractionCSVFormat.matches(header: feedHeader))
    }

    @Test func feedFormatMatchesOnlyItsHeader() {
        #expect(FeedCSVFormat.matches(header: feedHeader))
        #expect(!FeedCSVFormat.matches(header: contractionHeader))
    }

    @Test func unknownHeaderMatchesNothing() {
        let header = ["foo", "bar"]
        #expect(!ContractionCSVFormat.matches(header: header))
        #expect(!FeedCSVFormat.matches(header: header))
    }
}

@MainActor
struct CSVRoundTripTests {
    /// Reads an exported file and returns its header plus header-keyed rows.
    private func parsedRows(_ url: URL) throws -> (header: [String], rows: [[String: String]]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try #require(CSV.parse(text))
        return (parsed.header, parsed.rows.map { CSV.keyed(header: parsed.header, row: $0) })
    }

    @Test func contractionExportThenDecodePreservesStartAndEnd() throws {
        let ctx = PersistenceController.preview.viewContext
        let start1 = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let c1 = Contraction(context: ctx)
        c1.id = UUID(); c1.startDate = start1; c1.endDate = start1.addingTimeInterval(60)
        let start2 = start1.addingTimeInterval(300)
        let c2 = Contraction(context: ctx)
        c2.id = UUID(); c2.startDate = start2; c2.endDate = nil // in progress

        let url = try #require(CSVExporter.makeCSV(contractions: [c2, c1])) // unsorted input
        let (header, rows) = try parsedRows(url)
        #expect(ContractionCSVFormat.matches(header: header))

        let decoded = ContractionCSVFormat.decode(rows)
        #expect(decoded.skipped == 0)
        #expect(decoded.records.count == 2)
        // Export sorts oldest-first regardless of input order.
        #expect(abs(decoded.records[0].start.timeIntervalSince(start1)) < 0.01)
        #expect(decoded.records[0].end != nil)
        #expect(abs((decoded.records[0].end ?? .distantPast).timeIntervalSince(start1.addingTimeInterval(60))) < 0.01)
        #expect(abs(decoded.records[1].start.timeIntervalSince(start2)) < 0.01)
        #expect(decoded.records[1].end == nil)
    }

    @Test func feedExportThenDecodePreservesFieldsAndNoteWithComma() throws {
        let ctx = PersistenceController.preview.viewContext
        let ts = Date(timeIntervalSinceReferenceDate: 710_000_000)
        let bottle = Feed(context: ctx)
        bottle.id = UUID(); bottle.babyID = UUID(); bottle.timestamp = ts
        bottle.feedKind = .bottle; bottle.volume = 90; bottle.note = "post, nap" // comma must survive
        let breast = Feed(context: ctx)
        breast.id = UUID(); breast.babyID = UUID(); breast.timestamp = ts.addingTimeInterval(3600)
        breast.feedKind = .breast; breast.leftMinutes = 10; breast.rightMinutes = 12

        let url = try #require(CSVExporter.makeFeedCSV(feeds: [bottle, breast]))
        let (header, rows) = try parsedRows(url)
        #expect(FeedCSVFormat.matches(header: header))

        let decoded = FeedCSVFormat.decode(rows)
        #expect(decoded.skipped == 0)
        #expect(decoded.records.count == 2)

        let first = decoded.records[0]
        #expect(first.kind == .bottle)
        #expect(first.volume == 90)
        #expect(first.note == "post, nap")
        #expect(first.leftMinutes == nil)

        let second = decoded.records[1]
        #expect(second.kind == .breast)
        #expect(second.leftMinutes == 10)
        #expect(second.rightMinutes == 12)
        #expect(second.volume == nil)
    }

    @Test func decodeSkipsRowsWithoutAValidDate() {
        let rows: [[String: String]] = [
            ["start_iso8601": "", "end_iso8601": ""],
            ["start_iso8601": "not-a-date", "end_iso8601": ""],
        ]
        let decoded = ContractionCSVFormat.decode(rows)
        #expect(decoded.records.isEmpty)
        #expect(decoded.skipped == 2)
    }
}
