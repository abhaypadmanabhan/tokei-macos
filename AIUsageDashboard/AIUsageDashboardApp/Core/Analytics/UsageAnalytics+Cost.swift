import Foundation

/// Overview › Cost: API-equivalent dollars by day, priced from each provider's
/// `dailyModelUsage` through the same `PricingEngine` the Value tab uses, so the two can
/// never price a model differently. Dollars are known only where they were measured: a day an
/// agent with per-model data has tokens but no breakdown, or a day after its data ends (an
/// earlier day's save), is unknown, never $0. Days before the first per-model day anywhere are
/// left out and named by `pricedFrom`. A day with no tokens at all is a real $0.
public struct CostSummary: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let date: Date
        /// `nil`: not known that day (tokens without a per-model breakdown, or after the data ends).
        public let usd: Double?
    }

    public enum ProviderCost: Equatable, Sendable {
        /// Priced from per-model data; `partial` when some of its tokens had no price.
        case priced(usd: Double, partial: Bool)
        /// The provider's own logs carry the API cost of each request; one all-time total.
        case reportedAllTime(usd: Double)
        /// Tokens in the range, but no per-model data or no rate for any of them.
        case noPriceData
    }

    /// Priced dollars today; `nil` when today is not known (no per-model data reaches it).
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
    /// One point per day in the range from `pricedFrom`, oldest first.
    public let trend: [Point]
    /// Days in `trend` whose dollars are not known.
    public let unpricedDays: Int
    /// Providers with tokens in the range.
    public let providers: [ProviderID: ProviderCost]
}

extension UsageAnalytics {
    /// Providers whose logs record each request's API cost. Cursor's cost is the amount
    /// billed (often $0 on included plans), not an API estimate, so it is not one of them.
    public static let reportedCostProviders: Set<ProviderID> = [.cline, .opencode]

    /// One day's priced dollars, the tokens that were and were not priced, and whether the
    /// day's dollars are known at all.
    struct CostDay: Equatable {
        var usd = 0.0
        var pricedTokens = 0
        var unpricedTokens = 0
        var unknown = false

        mutating func add(_ other: CostDay) {
            usd += other.usd
            pricedTokens += other.pricedTokens
            unpricedTokens += other.unpricedTokens
            unknown = unknown || other.unknown
        }
    }

    public static func costSummary(
        snapshots: [ProviderSnapshot],
        range: UsageRange,
        pricing: PricingEngine,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> CostSummary {
        let today = calendar.startOfDay(for: now)
        let perProvider = Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.providerID, costDays(for: $0, pricing: pricing, calendar: calendar, today: today))
        })
        var days: [Date: CostDay] = [:]
        for providerDays in perProvider.values {
            for (day, cost) in providerDays { days[day, default: CostDay()].add(cost) }
        }
        let pricedFrom = snapshots
            .compactMap { $0.dailyModelUsage?.keys.map { calendar.startOfDay(for: $0) }.min() }
            .min()
        let bounds = dayBounds(dailyRange(for: range), calendar: calendar, today: today)
        let inRange = { (day: Date) in (bounds.start.map { day >= $0 } ?? true) && day <= bounds.end }

        let todayCost = days[today] ?? CostDay()
        let todayTokens = todayCost.pricedTokens + todayCost.unpricedTokens
        // No per-model data anywhere: no priced day at all, so no line and no total.
        let trend = pricedFrom.map { from in
            costTrend(days: days, from: max(bounds.start ?? from, from), to: bounds.end, calendar: calendar)
        } ?? []
        let known = trend.compactMap(\.usd)
        return CostSummary(
            todayUSD: pricedFrom.flatMap { $0 <= today && !todayCost.unknown ? todayCost.usd : nil },
            todayExcludedShare: todayTokens > 0 ? Double(todayCost.unpricedTokens) / Double(todayTokens) : 0,
            rangeUSD: known.isEmpty ? nil : known.reduce(0, +),
            pricedFrom: pricedFrom,
            rangeStartsBeforePricing: pricedFrom.map { from in bounds.start.map { $0 < from } ?? true } ?? false,
            delta: costDelta(
                days: days, range: range, calendar: calendar, today: today,
                modelled: snapshots.filter(\.hasModelBreakdown).map { perProvider[$0.providerID] ?? [:] }
            ),
            trend: trend,
            unpricedDays: trend.count - known.count,
            providers: providerCosts(snapshots: snapshots, perProvider: perProvider, inRange: inRange)
        )
    }

    /// A provider's days. A day with a per-model entry is priced model by model, and any tokens
    /// its total has beyond the breakdown are unpriced (never counted twice). For an agent with
    /// per-model data, a day with tokens and no breakdown, and every day after its data ends, is
    /// unknown. An agent with no per-model data at all only adds unpriced tokens.
    static func costDays(
        for snapshot: ProviderSnapshot,
        pricing: PricingEngine,
        calendar: Calendar,
        today: Date
    ) -> [Date: CostDay] {
        var days: [Date: CostDay] = [:]
        var named: [Date: Int] = [:]
        for (date, models) in snapshot.dailyModelUsage ?? [:] {
            let day = calendar.startOfDay(for: date)
            days[day] = days[day] ?? CostDay()
            for (model, usage) in models {
                let tokens = usage.totalTokens ?? 0
                named[day, default: 0] += tokens
                let usd = pricing.cost(model: model, tokens: usage)
                days[day]?.add(usd.map { CostDay(usd: $0, pricedTokens: tokens) } ?? CostDay(unpricedTokens: tokens))
            }
        }
        let totals = normalizedDailyTotals(snapshot.dailyTotals ?? [:], calendar: calendar).filter { $0.value > 0 }
        for (day, tokens) in totals {
            if let breakdown = named[day] {
                days[day]?.add(CostDay(unpricedTokens: max(0, tokens - breakdown)))
            } else {
                days[day] = CostDay(unpricedTokens: tokens, unknown: snapshot.hasModelBreakdown)
            }
        }
        guard snapshot.hasModelBreakdown,
              let last = ([snapshot.lastSyncedAt.map { calendar.startOfDay(for: $0) }] + days.keys.map { $0 })
                .compactMap({ $0 }).max(),
              var day = calendar.date(byAdding: .day, value: 1, to: last) else { return days }
        while day <= today {
            days[day, default: CostDay()].unknown = true
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
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
            let cost = days[day] ?? CostDay()
            points.append(CostSummary.Point(date: day, usd: cost.unknown ? nil : cost.usd))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    /// Like for like, as the token delta: complete days only, and only when every agent with
    /// per-model data is recorded from the earlier period's first day and fully priced on every
    /// compared day (a gap or an unpriced model is not a cheap day).
    private static func costDelta(
        days: [Date: CostDay],
        range: UsageRange,
        calendar: Calendar,
        today: Date,
        modelled: [[Date: CostDay]]
    ) -> Double? {
        guard let count = dayCount(for: range),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let previousStart = dayBounds(.previousDays(count), calendar: calendar, today: yesterday).start,
              !modelled.isEmpty,
              historiesCover(modelled.map { Set($0.filter { !$0.value.unknown }.keys) },
                             from: previousStart, to: yesterday),
              modelled.allSatisfy({ agent in
                  agent.allSatisfy { day, cost in
                      day < previousStart || day > yesterday || (!cost.unknown && cost.unpricedTokens == 0)
                  }
              }) else { return nil }
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
               let usd = snapshot.costUsage?.amount, usd >= 0, usd.isFinite {
                result[snapshot.providerID] = .reportedAllTime(usd: usd)
            } else if total.pricedTokens > 0 {
                result[snapshot.providerID] = .priced(usd: total.usd, partial: total.unpricedTokens > 0)
            } else {
                result[snapshot.providerID] = .noPriceData
            }
        }
        return result
    }

    /// Whether every history with data between `start` and `end` began on or before `start`. One
    /// that begins inside the period is only partly recorded there (Claude Code deletes old
    /// logs), so comparing totals across it would invent a change: the 30-day Overview read
    /// "▲ 2175.9%" because another agent's history reached back further. Days are start-of-day.
    static func historiesCover(_ histories: [Set<Date>], from start: Date, to end: Date) -> Bool {
        histories.allSatisfy { days in
            guard let first = days.min(), days.contains(where: { $0 >= start && $0 <= end }) else { return true }
            return first <= start
        }
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

extension ProviderSnapshot {
    /// Whether this agent reports tokens per model per day (what the Cost view can price).
    var hasModelBreakdown: Bool { dailyModelUsage?.isEmpty == false }
}
