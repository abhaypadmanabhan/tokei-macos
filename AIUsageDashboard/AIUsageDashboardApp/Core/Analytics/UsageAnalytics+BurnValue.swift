import Foundation

extension UsageAnalytics {
    /// Value's paired-provider rule, with value inputs instead of a defaults-backed store.
    /// Kept in Analytics so Burn can evaluate off-actor without reading preferences or a
    /// changing pricing cache. Parity with MaxxerValueEngine is covered by BurnEngineTests.
    static func burnMonthMultiple(
        snapshots: [ProviderSnapshot], monthlyPlanUSD: [ProviderID: Double],
        pricing: PricingEngine, now: Date, calendar: Calendar
    ) -> Double? {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        var value = 0.0, plans = 0.0
        for snapshot in snapshots {
            guard let plan = monthlyPlanUSD[snapshot.providerID], plan > 0, plan.isFinite else { continue }
            let amount: Double?
            if let days = snapshot.dailyModelUsage {
                let models = UsageAggregation.sumModels(days.compactMap { date, models in
                    date >= month.start && date <= now ? models : nil
                })
                let active = models.filter { ($0.value.totalTokens ?? 0) > 0 }
                let priced = active.compactMap { pricing.cost(model: $0.key, tokens: $0.value) }
                amount = active.isEmpty ? 0 : (priced.isEmpty ? nil : priced.reduce(0, +))
            } else {
                amount = burnLegacyMonthValue(snapshot, pricing: pricing, month: month, now: now)
            }
            if let amount { value += amount; plans += plan }
        }
        return plans > 0 ? value / plans : nil
    }

    private static func burnLegacyMonthValue(
        _ snapshot: ProviderSnapshot, pricing: PricingEngine, month: DateInterval, now: Date
    ) -> Double? {
        guard let usage = snapshot.monthUsage, usage.confidence != .unavailable,
              let total = usage.totalTokens else { return nil }
        let model: String
        switch snapshot.providerID {
        case .claudeCode: model = "claude-sonnet-4-6"
        case .codex: model = "gpt-5"
        case .cursor: model = "cursor-composer"
        case .antigravity, .cline, .opencode, .gemini, .copilot: return nil
        }
        guard let amount = pricing.cost(model: model, tokens: usage) else { return nil }
        guard let days = snapshot.dailyTotals else { return amount }
        let mtd = TokenArithmetic.sum(days.filter { $0.key >= month.start && $0.key <= now }.values.map { max(0, $0) })
        guard total > 0 else { return mtd == 0 ? amount : nil }
        return amount * min(Double(mtd) / Double(total), 1)
    }
}
