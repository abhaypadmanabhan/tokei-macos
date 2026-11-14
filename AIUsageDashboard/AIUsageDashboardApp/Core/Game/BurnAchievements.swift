import Foundation

extension BurnEngine {
    static func recordCandidates(
        history: BurnHistory, plans: [ProviderID: Double], multiple: Double?, month: Date,
        streak: BurnStreak, longestStreakStart: Date?, now: Date, calendar: Calendar
    ) -> [BurnRecord] {
        let priced = !history.dollars.isEmpty
        let values = priced ? history.dollars : history.tokens.mapValues(Double.init)
        let unit: BurnUnit = priced ? .usd : .tokens
        var result: [BurnRecord] = []
        if let best = values.sorted(by: { $0.key < $1.key }).max(by: { $0.value < $1.value }), best.value > 0 {
            result.append(BurnRecord(kind: .bestDay, value: best.value, unit: unit, achievedAt: best.key))
        }
        var weeks: [Date: Double] = [:]
        for (day, value) in values.sorted(by: { $0.key < $1.key }) {
            if let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start { weeks[start, default: 0] += value }
        }
        if let best = weeks.sorted(by: { $0.key < $1.key }).max(by: { $0.value < $1.value }), best.value > 0 {
            result.append(BurnRecord(kind: .bestWeek, value: best.value, unit: unit, achievedAt: best.key))
        }
        // For the current month use Value's paired-provider result (including its legacy
        // fallback). Older months can only be recovered from per-day priced history.
        if !plans.isEmpty {
            var monthValues: [Date: Double] = [:]
            var monthPlans: [Date: Double] = [:]
            for (id, plan) in plans.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let grouped = Dictionary(grouping: (history.providerDollars[id] ?? [:]).filter { $0.key <= now }.sorted { $0.key < $1.key }) {
                    calendar.dateInterval(of: .month, for: $0.key)?.start ?? $0.key
                }
                for (start, days) in grouped {
                    monthValues[start, default: 0] += days.map(\.value).reduce(0, +)
                    monthPlans[start, default: 0] += plan
                }
            }
            var months = monthValues
            for start in monthValues.keys {
                if let value = monthValues[start], let plan = monthPlans[start] { months[start] = value / plan }
            }
            months[month] = multiple
            if let best = months.sorted(by: { $0.key < $1.key }).max(by: { $0.value < $1.value }), best.value > 0 {
                result.append(BurnRecord(kind: .bestMonthMultiple, value: best.value, unit: nil, achievedAt: best.key))
            }
        }
        if streak.longest > 0, let longestStreakStart {
            result.append(BurnRecord(kind: .longestStreak, value: Double(streak.longest), unit: nil,
                                     achievedAt: longestStreakStart))
        }
        return result
    }

    static func badgeProgress(
        history: BurnHistory, multiple: Double?,
        outcomes: [BurnWindowOutcome], longestStreak: Int, now: Date, calendar: Calendar
    ) -> [BurnBadge: Double] {
        let maxTokens = Double(history.tokens.values.max() ?? 0)
        // History has already crossed BurnEligibility; even fallback products without a
        // configured price qualify as plan providers. There is no second badge-specific rule.
        let plannedValue = history.providerDollars.values.contains { $0.values.contains { $0 > 0 } }
        var maxAgents = 0
        for day in history.tokens.keys {
            maxAgents = max(maxAgents, history.providerTokens.values.filter { ($0[day] ?? 0) > 0 }.count)
        }
        // "In a week" means a completed calendar week, with at least one observed reset.
        // An empty week or an unfinished current week cannot award Nothing left.
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weeks = Dictionary(grouping: outcomes.filter { $0.resetAt < currentWeek }) {
            calendar.dateInterval(of: .weekOfYear, for: $0.resetAt)?.start ?? $0.resetAt
        }
        let nothingLeft = weeks.values.map { windows in
            min(1, (windows.map(\.finalUsedPercent).min() ?? 0) / 80)
        }.max() ?? 0
        let thresholds: [BurnBadge: Double] = [
            .firstBurn: plannedValue ? 1 : 0,
            .paidForItself: (multiple ?? 0), .maxxing: (multiple ?? 0) / 2, .goblinMode: (multiple ?? 0) / 5,
            .millionDay: maxTokens / 1_000_000, .tenMillionDay: maxTokens / 10_000_000,
            .ranItDry: (outcomes.filter { $0.windowType == .fiveHour || $0.windowType == .session }.map(\.finalUsedPercent).max() ?? 0) / 90,
            .fullWeek: (outcomes.filter { $0.windowType == .weekly }.map(\.finalUsedPercent).max() ?? 0) / 90,
            .streak3: Double(longestStreak) / 3, .streak7: Double(longestStreak) / 7,
            .streak30: Double(longestStreak) / 30, .fleet: Double(maxAgents) / 3, .nothingLeft: nothingLeft
        ]
        return thresholds.mapValues { min(1, max(0, $0)) }
    }
}
