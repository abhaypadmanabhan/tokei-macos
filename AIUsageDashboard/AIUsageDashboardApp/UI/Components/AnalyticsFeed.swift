import SwiftUI
import AIUsageDashboardCore

// WAVE-1 SAMPLE FEED — the single seam for the Wave-2 wiring step.
//
// These structs mirror the frozen `DashboardViewModel` analytics contract
// (Patch Bible §4) field-for-field. In Wave 1 (WP-1 not yet merged) the
// Overview + Provider Detail screens render from `.sample` / `.empty`
// instances, and every sample-fed widget is labeled with `SampleChip` so a
// dev build can never pass fake numbers off as real. Wave 2 replaces the
// `.sample` construction sites with the real VM props verbatim and deletes
// the chips; the view layouts don't change.

/// Overview-scope analytics (Bible §4 "Ranged overview" block).
struct OverviewAnalyticsFeed {
    var trend: [(date: Date, tokens: Int)]                     // ← overviewTrend
    var providerSplit: [(provider: ProviderID, tokens: Int)]   // ← providerSplit
    var delta: Double?                                         // ← overviewDelta
    var streak: (current: Int, longest: Int)                   // ← streak
    var bestDay: (date: Date, tokens: Int)?                    // ← bestDay
    var leastActiveDay: (date: Date, tokens: Int)?             // ← leastActiveDay
    var dailyAverage: Int?                                     // ← dailyAverage
    var heatmap: [[Int?]]?                                     // ← heatmap (1b; nil until hourly lands)
    /// True while this instance carries placeholder numbers (drives `SampleChip`).
    var isSample: Bool

    /// Deterministic placeholder series over the trailing `days` (default 14).
    static func sample(days: Int = 14) -> OverviewAnalyticsFeed {
        let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                      18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000,
                      24_100_000, 19_700_000, 14_300_000, 20_900_000]
        let today = Calendar.current.startOfDay(for: Date())
        let trend: [(date: Date, tokens: Int)] = (0..<max(2, days)).map { offset in
            let daysBack = max(2, days) - 1 - offset
            return (
                date: Calendar.current.date(byAdding: .day, value: -daysBack, to: today) ?? today,
                tokens: values[offset % values.count]
            )
        }
        let best = trend.max { $0.tokens < $1.tokens }
        let least = trend.min { $0.tokens < $1.tokens }
        let average = trend.map(\.tokens).reduce(0, +) / trend.count
        return OverviewAnalyticsFeed(
            trend: trend,
            providerSplit: [
                (provider: .claudeCode, tokens: 131_000_000),
                (provider: .codex, tokens: 48_200_000),
                (provider: .cursor, tokens: 21_700_000),
                (provider: .opencode, tokens: 9_400_000),
            ],
            delta: 18.2,
            streak: (current: 5, longest: 14),
            bestDay: best,
            leastActiveDay: least,
            dailyAverage: average,
            heatmap: nil,   // hourly source absent until WP-1 Phase 1b — honest empty
            isSample: true
        )
    }

    /// Honest nothing — what a brand-new install renders.
    static let empty = OverviewAnalyticsFeed(
        trend: [], providerSplit: [], delta: nil, streak: (0, 0),
        bestDay: nil, leastActiveDay: nil, dailyAverage: nil, heatmap: nil,
        isSample: false
    )
}

/// Per-provider detail analytics (Bible §4 "Per provider" block).
struct DetailAnalyticsFeed {
    var todayDelta: Double?                                    // ← overviewDelta-style hero delta
    var thisWeek: (peakDayWeekday: Int, peakDayTokens: Int, dailyAverage: Int, delta: Double?)?  // ← thisWeek(for:)
    var heatmap: [[Int?]]?                                     // ← heatmap(for:)
    var peakHour: (hour: Int, tokens: Int)?                    // ← peakHour(for:)
    var isSample: Bool

    static let sample = DetailAnalyticsFeed(
        todayDelta: 18.2,
        // weekday follows Calendar convention (1 = Sunday) — 4 = Wednesday.
        thisWeek: (peakDayWeekday: 4, peakDayTokens: 24_100_000, dailyAverage: 15_300_000, delta: 12.4),
        heatmap: nil,   // 1b gate
        peakHour: nil,  // 1b gate
        isSample: true
    )

    static let empty = DetailAnalyticsFeed(
        todayDelta: nil, thisWeek: nil, heatmap: nil, peakHour: nil, isSample: false
    )
}

/// Caps-mono tag marking a widget that renders placeholder numbers in Wave 1.
/// Removed in the Wave-2 wiring commit along with the sample constructors.
struct SampleChip: View {
    var body: some View {
        Text("SAMPLE")
            .font(.mono(size: 9))
            .tracking(0.6)
            .foregroundColor(PadzyTheme.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.5), lineWidth: 1)
            )
            .accessibilityLabel("Sample data")
    }
}

/// Shared date/weekday formatting for the analytics widgets.
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
}
