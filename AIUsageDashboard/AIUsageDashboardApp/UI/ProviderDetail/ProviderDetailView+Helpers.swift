import SwiftUI
import AIUsageDashboardCore

// Small shared conversions the drill-in's sections lean on — percent, pace, window naming.
// They sit apart from the view file because every section file uses them and none owns them.

extension ProviderDetailView {
    // MARK: - Shared helpers

    /// Utilization percent for a window, matching the app's established gauge idiom
    /// (`used / limit` when a limit is present, else `used` is already a percent).
    func usedPercent(_ window: QuotaWindow) -> Double? {
        guard let used = window.used else { return nil }
        if let limit = window.limit, limit > 0 { return used / limit * 100 }
        return used
    }

    func paceVerdict(_ window: QuotaWindow) -> PaceVerdict? {
        guard let pct = usedPercent(window),
              let pace = MaxxerMath.pace(usedPercent: pct, windowType: window.type,
                                         resetAt: window.resetAt, now: Date())
        else { return nil }
        return PaceVerdict(pct: pct, elapsed: pace.elapsedFraction)
    }

    /// This week's tokens: the provider's own weekly metric, else the trailing
    /// 7 days of trend, else unknown.
    var weekTokens: Int? {
        if let week = snapshot.weekUsage.totalTokens { return week }
        guard !trend.isEmpty else { return nil }
        return trend.suffix(7).reduce(0) { $0 + $1.tokens }
    }

    /// The provider's own trailing-7-day average (the 7 days before the latest),
    /// used for the today-vs-average delta. `nil` until there's ≥8 days of trend.
    var ownWeekAvg: Int? {
        guard trend.count >= 8 else { return nil }
        let prior = Array(trend.dropLast().suffix(7))
        guard !prior.isEmpty else { return nil }
        return prior.reduce(0) { $0 + $1.tokens } / prior.count
    }

    /// Human window label for rows + the gauge (`.label` wins; else a friendly name).
    func windowDisplayName(_ window: QuotaWindow) -> String {
        if let label = window.label, !label.isEmpty { return label }
        switch window.type {
        case .session: return "Session"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .fiveHour: return "5-hour"
        case .monthly: return "Monthly"
        case .credits: return "Credits"
        case .perModel: return "Per model"
        case .lifetime: return "Lifetime"
        }
    }

    /// Lowercased window phrase for the insight sentence ("weekly window", "quota").
    func insightWindowName(_ window: QuotaWindow) -> String {
        let base = windowDisplayName(window).lowercased()
        return base.contains("quota") ? base : "\(base) window"
    }
}
