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

    /// Caption for `overviewDelta` — the comparison is always against the
    /// PREVIOUS window of the same length, so the caption must follow the range.
    static func deltaCaption(_ range: UsageRange) -> String {
        switch range {
        case .today: return "vs yesterday"
        case .sevenDay, .week: return "vs prev 7 days"
        case .thirtyDay, .month: return "vs prev 30 days"
        case .ninetyDay: return "vs prev 90 days"
        case .lifetime, .custom: return "vs previous period"
        }
    }
}
