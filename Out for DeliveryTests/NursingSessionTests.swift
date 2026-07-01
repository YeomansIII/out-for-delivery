//
//  NursingSessionTests.swift
//  Out for DeliveryTests
//
//  Covers the live nursing timer's pure logic: per-side accumulation across switch /
//  pause / resume, commit rounding to whole minutes, and the next-side suggestion
//  (story 8.3). The session takes an injectable clock so the timing math is
//  deterministic; the haptics and SwiftUI rendering are validated on-device.
//

import Testing
import Foundation
import CoreData
@testable import Out_for_Delivery

struct NursingSessionTests {

    /// An isolated session with a controllable clock and a throwaway defaults suite.
    @MainActor
    private func makeSession(clock: @escaping () -> Date) -> NursingSession {
        let defaults = UserDefaults(suiteName: "nursing.test.\(UUID().uuidString)")!
        return NursingSession(now: clock, store: defaults, storeKey: "test")
    }

    @MainActor @Test func accumulatesPerSideAcrossSwitch() {
        var t = Date(timeIntervalSince1970: 0)
        let s = makeSession(clock: { t })
        let baby = UUID()

        s.start(.left, for: baby)
        t += 65                       // 65s on the left
        s.tap(.right, for: baby)      // switching folds the left segment, starts the right
        #expect(Int(s.seconds(for: .left).rounded()) == 65)

        t += 120                      // 120s on the right
        let result = s.commit()
        #expect(result.leftMinutes == 1)    // round(65/60)
        #expect(result.rightMinutes == 2)   // round(120/60)
    }

    @MainActor @Test func pauseFreezesTimeAndResumeContinues() {
        var t = Date(timeIntervalSince1970: 0)
        let s = makeSession(clock: { t })
        let baby = UUID()

        s.start(.left, for: baby)
        t += 30
        s.tap(.left, for: baby)       // tapping the running side pauses it
        #expect(s.isRunning == false)
        #expect(Int(s.seconds(for: .left).rounded()) == 30)

        t += 1000                     // time passes while paused — must not accrue
        #expect(Int(s.seconds(for: .left).rounded()) == 30)

        s.start(.left, for: baby)     // resume
        t += 30
        #expect(Int(s.seconds(for: .left).rounded()) == 60)
    }

    @MainActor @Test func subMinuteSidesRoundAwayToNil() {
        var t = Date(timeIntervalSince1970: 0)
        let s = makeSession(clock: { t })
        s.start(.left, for: UUID())
        t += 20                       // 20s rounds to 0 minutes
        let result = s.commit()
        #expect(result.leftMinutes == nil)
        #expect(result.rightMinutes == nil)
    }

    @MainActor @Test func startedAtIsTheFirstStart() {
        var t = Date(timeIntervalSince1970: 1000)
        let s = makeSession(clock: { t })
        let baby = UUID()
        s.start(.left, for: baby)
        t += 500
        s.tap(.right, for: baby)
        let result = s.commit()
        #expect(result.startedAt == Date(timeIntervalSince1970: 1000))
    }

    @MainActor @Test func resetClearsEverything() {
        var t = Date(timeIntervalSince1970: 0)
        let s = makeSession(clock: { t })
        s.start(.left, for: UUID())
        t += 120
        s.reset()
        #expect(s.isRunning == false)
        #expect(s.hasContent == false)
        #expect(s.seconds(for: .left) == 0)
        #expect(s.seconds(for: .right) == 0)
        #expect(s.babyID == nil)
    }

    // MARK: Next-side suggestion (story 8.3)

    @MainActor @Test func suggestsOppositeOfHeavierSide() {
        let context = PersistenceController.preview.viewContext
        let feed = Feed(context: context)
        feed.id = UUID(); feed.babyID = UUID(); feed.timestamp = Date()
        feed.feedKind = .breast

        feed.leftMinutes = 12
        feed.rightMinutes = 5
        #expect(NursingSession.suggestedStartSide(lastNursingFeed: feed) == .right)

        feed.leftMinutes = 4
        feed.rightMinutes = 10
        #expect(NursingSession.suggestedStartSide(lastNursingFeed: feed) == .left)
    }

    @MainActor @Test func suggestsLeftWithNoHistory() {
        #expect(NursingSession.suggestedStartSide(lastNursingFeed: nil) == .left)
    }

    @MainActor @Test func suggestsLeftWhenLastFeedWasNotNursing() {
        let context = PersistenceController.preview.viewContext
        let feed = Feed(context: context)
        feed.id = UUID(); feed.babyID = UUID(); feed.timestamp = Date()
        feed.feedKind = .bottle
        feed.volume = 90
        #expect(NursingSession.suggestedStartSide(lastNursingFeed: feed) == .left)
    }
}
