//
//  NewbornStyle.swift
//  Out for Delivery
//
//  Shared visual vocabulary for newborn mode: the per-event-type accent colors and
//  SF Symbols used across the dashboard, editors, and lists, plus the diaper-color
//  swatches. Colors are semantic tints layered over system materials so the UI
//  still adapts to light/dark — Liquid Glass and tints are accent only; the medical
//  numbers themselves stay in solid, legible cards (see CLAUDE.md conventions).
//

import SwiftUI

/// The three newborn event types this build tracks, each with a consistent accent
/// color and icon so a glance reads the same on the dashboard, editor, and lists.
enum NewbornEvent: CaseIterable {
    case feed
    case diaper
    case pump

    var tint: Color {
        switch self {
        case .feed: return .orange
        case .diaper: return .green
        case .pump: return .pink
        }
    }

    var symbolName: String {
        switch self {
        case .feed: return "drop.fill"
        case .diaper: return "humidity.fill"
        case .pump: return "waveform.path.ecg"
        }
    }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .diaper: return "Diaper"
        case .pump: return "Pump"
        }
    }
}

extension DiaperColor {
    /// The swatch shown in the color picker and on dirty-diaper rows. Mirrors the
    /// stool-color reference shades from the design.
    var swatch: Color {
        switch self {
        case .yellow: return Color(red: 0.85, green: 0.72, blue: 0.35)
        case .green: return Color(red: 0.60, green: 0.63, blue: 0.35)
        case .brown: return Color(red: 0.54, green: 0.42, blue: 0.24)
        case .black: return Color(red: 0.23, green: 0.17, blue: 0.13)
        case .red: return Color(red: 0.71, green: 0.34, blue: 0.29)
        case .unknown: return Color(.systemGray3)
        }
    }
}
