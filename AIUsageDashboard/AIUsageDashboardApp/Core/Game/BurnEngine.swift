import Foundation

public enum BurnEngine {
    /// Pure: no clock, preferences, pricing cache, file access or notifications inside.
    public static func evaluate(
        snapshots: [ProviderSnapshot], monthlyPlanUSD: [ProviderID: Double], quotaSamples: [QuotaSample],
        state: BurnState, now: Date, calendar: Calendar, pricing: PricingEngine,
        hiddenProviders: Set<ProviderID> = [], emitMoments: Bool = true
    ) -> (snapshot: BurnSnapshot, state: BurnState) {
        let visible = snapshots.filter { !hiddenProviders.contains($0.providerID) }
        let history = BurnHistory(snapshots: visible, pricing: pricing, now: now, calendar: calendar)
        let plans = monthlyPlanUSD.filter { id, cost in
            cost.isFinite && cost > 0 && visible.contains { $0.providerID == id }
        }
        let monthlyUSD = plans.values.reduce(0, +)
        let today = calendar.startOfDay(for: now)
        let goal = history.goal(on: today, monthlyUSD: monthlyUSD, calendar: calendar)
        let burned = goal?.unit == .usd ? history.todayUSD : history.tokens[today].map(Double.init)
        let progress = goal.flatMap { goal in burned.map { $0 / goal.target } }
        let day = BurnDay(day: today, valueUSD: history.todayUSD, tokens: history.tokens[today] ?? 0,
                          goal: goal, progress: progress)
        let hits = Set(history.tokens.keys).union(history.dollars.keys).filter {
            history.hit(on: $0, monthlyUSD: monthlyUSD, calendar: calendar)
        }.sorted()
        let streak = streak(hits: hits, today: today, todayHit: day.goalHit,
                            storedLongest: state.longestStreak, calendar: calendar)
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? today
        let multiple = UsageAnalytics.burnMonthMultiple(snapshots: visible, monthlyPlanUSD: plans,
                                                       pricing: pricing, now: now, calendar: calendar)
        let tier = multiple.map(tier(for:))
        let outcomes = windowOutcomes(samples: quotaSamples.filter { !hiddenProviders.contains($0.providerID) }, now: now)
        let since = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = outcomes.filter { $0.resetAt >= since }
        var next = state
        var moments: [BurnMoment] = []
        let candidates = recordCandidates(history: history, plans: plans, multiple: multiple,
                                          month: month, streak: streak, now: now, calendar: calendar)
        for record in candidates {
            let old = next.records[record.kind.rawValue]
            // Units cannot be compared. Changing from token goals to dollar goals seeds
            // that record without claiming that dollars beat a number of tokens.
            if old == nil || old?.unit != record.unit?.rawValue || record.value > (old?.value ?? 0) {
                next.records[record.kind.rawValue] = BurnState.Record(record)
                if state.initialized && old?.unit == record.unit?.rawValue && old != nil {
                    moments.append(.record(record.kind))
                }
            }
        }
        next.longestStreak = streak.longest
        let bestMultiple = max(multiple ?? 0, next.records[BurnRecordKind.bestMonthMultiple.rawValue]?.value ?? 0)
        let badges = badgeProgress(history: history, plans: plans, multiple: bestMultiple,
                                   outcomes: outcomes, longestStreak: streak.longest, now: now, calendar: calendar)
        for badge in BurnBadge.allCases where (badges[badge] ?? 0) >= 1 && next.badges[badge.rawValue] == nil {
            next.badges[badge.rawValue] = now
            if state.initialized { moments.append(.badge(badge)) }
        }
        if state.initialized, state.tierMonth == month, let tier,
           let old = state.tier.flatMap(MaxxerTier.init(rawValue:)), tierRank(tier) > tierRank(old) {
            moments.append(.tierUp(tier))
        }
        next.tierMonth = month
        next.tier = tier?.rawValue
        next.initialized = true
        func record(_ kind: BurnRecordKind) -> BurnRecord? { next.records[kind.rawValue]?.burnRecord(kind: kind) }
        let snapshot = BurnSnapshot(
            generatedAt: now, today: day, streak: streak,
            expiring: ExpiringHeadroomFinder.find(in: visible, now: now),
            records: BurnRecords(bestDay: record(.bestDay), bestWeek: record(.bestWeek),
                                 bestMonthMultiple: record(.bestMonthMultiple), longestStreak: record(.longestStreak)),
            leaderboard: leaderboard(history: history, visible: visible, now: now, calendar: calendar),
            badges: BurnBadge.allCases.map { badge in
                BurnBadgeProgress(badge: badge, unlockedAt: next.badges[badge.rawValue],
                                  progress: next.badges[badge.rawValue] != nil ? 1 : badges[badge])
            }, recentWindows: recent, tier: tier, monthValueMultiple: multiple,
            moments: emitMoments ? moments : []
        )
        return (snapshot, next)
    }

    static func tier(for multiple: Double) -> MaxxerTier {
        switch multiple {
        case ..<0.25: return .idle
        case ..<1: return .warming
        case ..<2: return .breakEven
        case ..<5: return .maxxing
        default: return .goblinMode
        }
    }

    private static func tierRank(_ tier: MaxxerTier) -> Int { MaxxerTier.allCases.firstIndex(of: tier) ?? 0 }

    private static func streak(hits: [Date], today: Date, todayHit: Bool,
                               storedLongest: Int, calendar: Calendar) -> BurnStreak {
        var run = 0, longest = 0
        var previous: Date?
        for day in hits {
            run = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        let hitSet = Set(hits)
        var end = todayHit ? today : calendar.date(byAdding: .day, value: -1, to: today)
        var current = 0
        while let date = end, hitSet.contains(date) {
            current += 1
            end = calendar.date(byAdding: .day, value: -1, to: date)
        }
        return BurnStreak(current: current, longest: max(storedLongest, longest), todayHit: todayHit)
    }

    private static func leaderboard(history: BurnHistory, visible: [ProviderSnapshot],
                                    now: Date, calendar: Calendar) -> [BurnLeaderboardEntry] {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let entries = visible.map { snapshot -> (ProviderID, Double?, Int) in
            let usd = (history.providerDollars[snapshot.providerID] ?? [:]).filter { $0.key >= start && $0.key <= now }.values
            let tokens = (history.providerTokens[snapshot.providerID] ?? [:]).filter { $0.key >= start && $0.key <= now }.values
            return (snapshot.providerID, usd.isEmpty ? nil : usd.reduce(0, +), TokenArithmetic.sum(tokens))
        }.sorted {
            if $0.1 != $1.1 { return ($0.1 ?? -1) > ($1.1 ?? -1) }
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            return $0.0.rawValue < $1.0.rawValue
        }
        return entries.enumerated().map { rank, entry in
            BurnLeaderboardEntry(providerID: entry.0, rank: rank + 1, valueUSD: entry.1, tokens: entry.2)
        }
    }
}
