//
//  FeedReminderTests.swift
//  Out for DeliveryTests
//
//  Covers the pure feed-on-demand reminder timing (FeedMath). The scheduling
//  itself (AlarmKit) and SwiftData persistence are validated on-device.
//

import Testing
import Foundation
@testable import Out_for_Delivery

struct FeedReminderTests {

    private let threeHours: TimeInterval = 3 * 60 * 60

    @Test func freshFeedArmsFullInterval() {
        let now = Date()
        let remaining = FeedMath.remainingUntilFire(lastFeed: now, interval: threeHours, now: now)
        #expect(remaining == threeHours)
    }

    @Test func loggingBeforeLapseResetsToFullIntervalFromLatestFeed() {
        let now = Date()
        // A feed logged 30 minutes ago should leave 2h30m on a 3h reminder...
        let earlier = now.addingTimeInterval(-30 * 60)
        #expect(FeedMath.remainingUntilFire(lastFeed: earlier, interval: threeHours, now: now) == threeHours - 30 * 60)

        // ...and a brand-new feed (now) resets it back to the full interval.
        #expect(FeedMath.remainingUntilFire(lastFeed: now, interval: threeHours, now: now) == threeHours)
    }

    @Test func overdueFeedClampsToMinimumRatherThanSkipping() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-5 * 60 * 60) // 5h ago, past a 3h reminder
        let remaining = FeedMath.remainingUntilFire(lastFeed: longAgo, interval: threeHours, now: now, minimum: 1)
        #expect(remaining == 1)
    }

    @Test func noFeedYetCountsFromNow() {
        let now = Date()
        let fire = FeedMath.reminderFireDate(lastFeed: nil, interval: threeHours, now: now)
        #expect(fire == now.addingTimeInterval(threeHours))
    }

    @Test func fireDateIsLastFeedPlusInterval() {
        let last = Date(timeIntervalSince1970: 1_000_000)
        let fire = FeedMath.reminderFireDate(lastFeed: last, interval: threeHours, now: Date())
        #expect(fire == last.addingTimeInterval(threeHours))
    }
}
