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

    /// The active range as it reads mid-sentence: "5.09B tokens in the last 7 days",
    /// "Agents in the last 7 days".
    static func rangePhrase(_ range: UsageRange) -> String {
        switch range {
        case .today: return "today"
        case .sevenDay, .week: return "in the last 7 days"
        case .thirtyDay, .month: return "in the last 30 days"
        case .ninetyDay: return "in the last 90 days"
        case .lifetime: return "all time"
        case .custom: return "in this range"
        }
    }

    /// "excludes 3% of tokens with no price data" under the Cost headline; `nil` when every
    /// token was priced.
    static func excludedPhrase(_ share: Double) -> String? {
        guard share > 0 else { return nil }
        let percent = share * 100
        return "excludes \(percent < 1 ? "under 1" : String(Int(percent.rounded())))% of tokens with no price data"
    }

    /// What the Cost chart's frame says when it cannot draw a line (it needs two priced days):
    /// "No priced days" only when there are none; one priced day is real, just not a line yet.
    static func costChartEmptyText(pricedDays: Int) -> String? {
        switch pricedDays {
        case 0: return "No priced days in this range"
        case 1: return "Not enough history yet"
        default: return nil
        }
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
