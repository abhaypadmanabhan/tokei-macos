import Foundation

/// Overview › Cost: API-equivalent dollars by day, priced from each provider's
/// `dailyModelUsage` through the same `PricingEngine` the Value tab uses, so the two can
/// never price a model differently. A day a provider has tokens but no per-model entry
/// counts those tokens as unpriced; days before the first per-model day anywhere are a gap
/// (no point, no $0), named by `pricedFrom`.
public struct CostSummary: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let date: Date
        public let usd: Double
    }

    public enum ProviderCost: Equatable, Sendable {
        /// Priced from per-model data; `partial` when some of its tokens had no price.
        case priced(usd: Double, partial: Bool)
        /// The provider's own logs carry the API cost of each request; one all-time total.
        case reportedAllTime(usd: Double)
        /// Tokens in the range, but no per-model data or no rate for any of them.
        case noPriceData
    }

    /// Priced dollars today; `nil` when no per-model data reaches today.
    public let todayUSD: Double?
    /// Share of today's tokens left out for having no price, 0…1.
    public let todayExcludedShare: Double
    /// Priced dollars over the range's priced days; `nil` when none of it is priced.
    public let rangeUSD: Double?
    /// The first day with per-model data; earlier days are a gap.
    public let pricedFrom: Date?
    /// The range reaches back before `pricedFrom`, so `rangeUSD` covers less than the range.
    public let rangeStartsBeforePricing: Bool
    /// Last N complete days against the N before, only when both periods are fully priced.
    public let delta: Double?
    /// One point per priced day in the range, oldest first.
    public let trend: [Point]
    /// Providers with tokens in the range.
    public let providers: [ProviderID: ProviderCost]
}

extension UsageAnalytics {
    /// Providers whose logs record each request's API cost. Cursor's cost is the amount
    /// billed (often $0 on included plans), not an API estimate, so it is not one of them.
    public static let reportedCostProviders: Set<ProviderID> = [.cline, .opencode]

    /// One day's priced dollars and the tokens that were and were not priced.
    struct CostDay: Equatable {
        var usd = 0.0
        var pricedTokens = 0
        var unpricedTokens = 0

        mutating func add(_ other: CostDay) {
            usd += other.usd
            pricedTokens += other.pricedTokens
            unpricedTokens += other.unpricedTokens
        }
    }

    public static func costSummary(
        snapshots: [ProviderSnapshot],
        range: UsageRange,
        pricing: PricingEngine,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> CostSummary {
        let perProvider = Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.providerID, costDays(for: $0, pricing: pricing, calendar: calendar))
        })
        var days: [Date: CostDay] = [:]
        for providerDays in perProvider.values {
            for (day, cost) in providerDays { days[day, default: CostDay()].add(cost) }
        }
        let pricedFrom = snapshots
            .compactMap { $0.dailyModelUsage?.keys.map { calendar.startOfDay(for: $0) }.min() }
            .min()
        let today = calendar.startOfDay(for: now)
        let bounds = dayBounds(dailyRange(for: range), calendar: calendar, today: today)
        let inRange = { (day: Date) in (bounds.start.map { day >= $0 } ?? true) && day <= bounds.end }

        let todayCost = days[today] ?? CostDay()
        let todayTokens = todayCost.pricedTokens + todayCost.unpricedTokens
        // No per-model data anywhere: no priced day at all, so no line and no total.
        let trend = pricedFrom.map { from in
            costTrend(days: days, from: max(bounds.start ?? from, from), to: bounds.end, calendar: calendar)
        } ?? []
        return CostSummary(
            todayUSD: pricedFrom.flatMap { $0 <= today ? todayCost.usd : nil },
            todayExcludedShare: todayTokens > 0 ? Double(todayCost.unpricedTokens) / Double(todayTokens) : 0,
            rangeUSD: trend.isEmpty ? nil : trend.map(\.usd).reduce(0, +),
            pricedFrom: pricedFrom,
            rangeStartsBeforePricing: pricedFrom.map { from in bounds.start.map { $0 < from } ?? true } ?? false,
            delta: costDelta(days: days, range: range, pricedFrom: pricedFrom, calendar: calendar, today: today),
            trend: trend,
            providers: providerCosts(snapshots: snapshots, perProvider: perProvider, inRange: inRange)
        )
    }

    /// A provider's days: priced from its per-model entry when it has one that day, else
    /// that day's tokens count as unpriced.
    static func costDays(
        for snapshot: ProviderSnapshot,
        pricing: PricingEngine,
        calendar: Calendar
    ) -> [Date: CostDay] {
        var days: [Date: CostDay] = [:]
        for (date, models) in snapshot.dailyModelUsage ?? [:] {
            let day = calendar.startOfDay(for: date)
            for (model, usage) in models {
                let tokens = usage.totalTokens ?? 0
                if let usd = pricing.cost(model: model, tokens: usage) {
                    days[day, default: CostDay()].add(CostDay(usd: usd, pricedTokens: tokens))
                } else {
                    days[day, default: CostDay()].add(CostDay(unpricedTokens: tokens))
                }
            }
        }
        let modelled = Set(days.keys)
        for (day, tokens) in normalizedDailyTotals(snapshot.dailyTotals ?? [:], calendar: calendar)
        where tokens > 0 && !modelled.contains(day) {
            days[day] = CostDay(unpricedTokens: tokens)
        }
        return days
    }

    private static func costTrend(
        days: [Date: CostDay],
        from start: Date?,
        to end: Date,
        calendar: Calendar
    ) -> [CostSummary.Point] {
        guard var day = start, day <= end else { return [] }
        var points: [CostSummary.Point] = []
        while day <= end {
            points.append(CostSummary.Point(date: day, usd: days[day]?.usd ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    /// Like for like, as the token delta: complete days only, and only when both periods
    /// lie wholly on or after `pricedFrom` (a gap is not a cheap week).
    private static func costDelta(
        days: [Date: CostDay],
        range: UsageRange,
        pricedFrom: Date?,
        calendar: Calendar,
        today: Date
    ) -> Double? {
        guard let count = dayCount(for: range), let pricedFrom,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let previousStart = dayBounds(.previousDays(count), calendar: calendar, today: yesterday).start,
              previousStart >= pricedFrom else { return nil }
        let cents = { (bounds: (start: Date?, end: Date)) -> Int in
            let usd = days.filter { day, _ in day >= (bounds.start ?? day) && day <= bounds.end }
                .values.map(\.usd).reduce(0, +)
            return Int((usd * 100).rounded())
        }
        return delta(
            current: cents(dayBounds(.days(count), calendar: calendar, today: yesterday)),
            previous: cents(dayBounds(.previousDays(count), calendar: calendar, today: yesterday))
        )
    }

    private static func providerCosts(
        snapshots: [ProviderSnapshot],
        perProvider: [ProviderID: [Date: CostDay]],
        inRange: (Date) -> Bool
    ) -> [ProviderID: CostSummary.ProviderCost] {
        var result: [ProviderID: CostSummary.ProviderCost] = [:]
        for snapshot in snapshots {
            var total = CostDay()
            for (day, cost) in perProvider[snapshot.providerID] ?? [:] where inRange(day) { total.add(cost) }
            guard total.pricedTokens + total.unpricedTokens > 0 else { continue }
            if snapshot.dailyModelUsage == nil, reportedCostProviders.contains(snapshot.providerID),
               let usd = snapshot.costUsage?.amount, usd > 0 {
                result[snapshot.providerID] = .reportedAllTime(usd: usd)
            } else if total.pricedTokens > 0 {
                result[snapshot.providerID] = .priced(usd: total.usd, partial: total.unpricedTokens > 0)
            } else {
                result[snapshot.providerID] = .noPriceData
            }
        }
        return result
    }

    /// First and last day of `range` relative to `today`; `start` is `nil` for all time.
    static func dayBounds(_ range: DailyRange, calendar: Calendar, today: Date) -> (start: Date?, end: Date) {
        switch range {
        case .all:
            return (nil, today)
        case .days(let count):
            return (calendar.date(byAdding: .day, value: -(count - 1), to: today), today)
        case .previousDays(let count):
            return (calendar.date(byAdding: .day, value: -(count * 2 - 1), to: today),
                    calendar.date(byAdding: .day, value: -count, to: today) ?? today)
        case let .custom(start, end):
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        }
    }
}
