//
//  ContractionActivityAttributes.swift
//  Out for Delivery
//
//  Shared between the app target and the (to-be-added) widget extension target.
//  Add this file's target membership to the widget extension when it exists.
//

import Foundation
import ActivityKit

public struct ContractionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Phase: String, Codable {
            case contracting
            case resting
        }

        public var phase: Phase
        public var currentStart: Date?
        public var lastStart: Date?
        public var lastDuration: TimeInterval?
        public var lastInterval: TimeInterval?
        /// Total contractions ever logged.
        public var count: Int
        /// Contractions in the current session.
        public var sessionCount: Int
        public var avgInterval: TimeInterval?
        public var avgDuration: TimeInterval?
        public var patternMet: Bool

        public init(
            phase: Phase,
            currentStart: Date? = nil,
            lastStart: Date? = nil,
            lastDuration: TimeInterval? = nil,
            lastInterval: TimeInterval? = nil,
            count: Int = 0,
            sessionCount: Int = 0,
            avgInterval: TimeInterval? = nil,
            avgDuration: TimeInterval? = nil,
            patternMet: Bool = false
        ) {
            self.phase = phase
            self.currentStart = currentStart
            self.lastStart = lastStart
            self.lastDuration = lastDuration
            self.lastInterval = lastInterval
            self.count = count
            self.sessionCount = sessionCount
            self.avgInterval = avgInterval
            self.avgDuration = avgDuration
            self.patternMet = patternMet
        }
    }

    public var title: String

    public init(title: String = "Contractions") {
        self.title = title
    }
}
