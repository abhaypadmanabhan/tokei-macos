import Foundation

/// Uses the Cost view's daily pricing, including its unknown-day semantics.
struct BurnHistory {
    let tokens: [Date: Int]
    let dollars: [Date: Double]
    let providerTokens: [ProviderID: [Date: Int]]
    let providerDollars: [ProviderID: [Date: Double]]
    let todayUSD: Double?

    init(snapshots: [ProviderSnapshot], pricing: PricingEngine, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        var totals: [Date: Int] = [:]
        var byProvider: [ProviderID: [Date: Int]] = [:]
        var usdByProvider: [ProviderID: [Date: Double]] = [:]
        for snapshot in snapshots {
            var days = UsageAnalytics.normalizedDailyTotals(snapshot.dailyTotals ?? [:], calendar: calendar)
                .filter { $0.key <= today }
            // A fresh provider without history still knows today's total. Saved totals from
            // an earlier day cannot become today's burn.
            if days[today] == nil, let synced = snapshot.lastSyncedAt,
               calendar.isDate(synced, inSameDayAs: now), let count = snapshot.todayUsage.totalTokens {
                days[today] = max(0, count)
            }
            days = days.mapValues { max(0, $0) }
            byProvider[snapshot.providerID] = days
            totals.merge(days, uniquingKeysWith: TokenArithmetic.adding)
            let costs = UsageAnalytics.costDays(for: snapshot, pricing: pricing, calendar: calendar, today: today)
            usdByProvider[snapshot.providerID] = costs.compactMapValues { $0.unknown ? nil : $0.usd }
        }
        let cost = UsageAnalytics.costSummary(snapshots: snapshots, range: .lifetime,
                                              pricing: pricing, calendar: calendar, now: now)
        tokens = totals
        dollars = Dictionary(uniqueKeysWithValues: cost.trend.compactMap { point in
            point.usd.map { (point.date, $0) }
        })
        providerTokens = byProvider
        providerDollars = usdByProvider
        todayUSD = cost.todayUSD
    }

    func goal(on day: Date, monthlyUSD: Double, calendar: Calendar) -> BurnGoal? {
        if monthlyUSD > 0, let days = calendar.range(of: .day, in: .month, for: day)?.count {
            return BurnGoal(unit: .usd, target: monthlyUSD / Double(days))
        }
        let start = calendar.date(byAdding: .day, value: -30, to: day) ?? day
        let active = tokens.filter { $0.key >= start && $0.key < day && $0.value > 0 }.values.sorted()
        guard !active.isEmpty else { return nil }
        let middle = active.count / 2
        let median = active.count.isMultiple(of: 2)
            ? Double(active[middle - 1]) / 2 + Double(active[middle]) / 2 : Double(active[middle])
        return BurnGoal(unit: .tokens, target: median)
    }

    func hit(on day: Date, monthlyUSD: Double, calendar: Calendar) -> Bool {
        guard let goal = goal(on: day, monthlyUSD: monthlyUSD, calendar: calendar) else { return false }
        let value = goal.unit == .usd ? dollars[day] : tokens[day].map(Double.init)
        return (value ?? 0) >= goal.target
    }
}
