import Foundation
import AIUsageDashboardCore

/// Shared date/weekday/range formatting for the analytics widgets (Overview,
/// Provider Detail, menu-bar popover). Pure formatting — all analytics values
/// come from the frozen `DashboardViewModel` §4 surface.
enum AnalyticsFormat {
    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    /// `weekday` in Calendar convention (1 = Sunday).
    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = (weekday - 1) % symbols.count
        return symbols[index < 0 ? index + symbols.count : index].uppercased()
    }

    /// Hour 0…23 → "9AM" / "12PM" style label.
    static func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        switch normalized {
        case 0: return "12AM"
        case 12: return "12PM"
        case 1...11: return "\(normalized)AM"
        default: return "\(normalized - 12)PM"
        }
    }

    /// Chart-header label for the active range.
    static func rangeTitle(_ range: UsageRange) -> String {
        switch range {
        case .today: return "TODAY"
        case .sevenDay, .week: return "LAST 7 DAYS"
        case .thirtyDay, .month: return "LAST 30 DAYS"
        case .ninetyDay: return "LAST 90 DAYS"
        case .lifetime: return "LIFETIME"
        case .custom: return "CUSTOM RANGE"
        }
    }

    /// "excludes 3% of tokens with no price data" under the Cost headline; `nil` when every
    /// token was priced.
    static func excludedPhrase(_ share: Double) -> String? {
        guard share > 0 else { return nil }
        let percent = share * 100
        return "excludes \(percent < 1 ? "under 1" : String(Int(percent.rounded())))% of tokens with no price data"
    }

    /// "priced from Oct 1": where the priced days start when the range reaches further back.
    static func pricedFrom(_ date: Date) -> String {
        "priced from \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Caption for `overviewDelta`. The comparison is complete days against the same number
    /// of complete days before them (today's part-day is left out of both), and the caption
    /// says so, so the arrow is never read as "today vs a full day".
    static func deltaCaption(_ range: UsageRange) -> String {
        switch range {
        case .today: return "yesterday vs the day before"
        case .sevenDay, .week: return "last 7 full days vs the 7 before"
        case .thirtyDay, .month: return "last 30 full days vs the 30 before"
        case .ninetyDay: return "last 90 full days vs the 90 before"
        case .lifetime, .custom: return "vs previous period"
        }
    }
}
