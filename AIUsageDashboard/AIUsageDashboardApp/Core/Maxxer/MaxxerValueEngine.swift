import Foundation

public enum MaxxerValueEngine {
    public static func scorecard(
        snapshots: [ProviderSnapshot],
        planCosts: MaxxerPlanCostStore,
        now: Date,
        pricing: PricingEngine = PricingEngine(table: PricingService.cachedTable())
    ) -> MaxxerScorecard {
        let providers = snapshots.map { snapshot in
            providerValue(for: snapshot, planCosts: planCosts, pricing: pricing, now: now)
        }

        // Totals compare like with like: only providers where BOTH sides are
        // known participate, so one priced-but-unplanned provider can't inflate
        // the headline multiple (its usage still shows on its own row).
        let pairedProviders = providers.filter {
            $0.apiEquivalentUSD != nil && $0.planMonthlyUSD != nil
        }
        let totalAPIEquivalentUSD = sumOrNil(pairedProviders.compactMap(\.apiEquivalentUSD))
        let totalPlanUSD = sumOrNil(pairedProviders.compactMap(\.planMonthlyUSD))
        let totalValueMultiple = totalAPIEquivalentUSD.flatMap { apiEquivalentUSD in
            totalPlanUSD.map { apiEquivalentUSD / $0 }
        }

        return MaxxerScorecard(
            providers: providers,
            totalAPIEquivalentUSD: totalAPIEquivalentUSD,
            totalPlanUSD: totalPlanUSD,
            totalValueMultiple: totalValueMultiple,
            tier: totalValueMultiple.map(tier(for:))
        )
    }

    private static func providerValue(
        for snapshot: ProviderSnapshot,
        planCosts: MaxxerPlanCostStore,
        pricing: PricingEngine,
        now: Date
    ) -> MaxxerProviderValue {
        let providerID = snapshot.providerID.rawValue
        let planMonthlyUSD = planCosts.monthlyUSD(for: providerID)
        let models = modelValues(for: snapshot, pricing: pricing, now: now)
        let cost = snapshot.dailyModelUsage == nil
            ? apiEquivalentCost(for: snapshot, pricing: pricing, now: now)
            : modelCost(models)
        let valueMultiple = cost.amountUSD.flatMap { amount in
            planMonthlyUSD.map { amount / $0 }
        }

        return MaxxerProviderValue(
            providerID: providerID,
            apiEquivalentUSD: cost.amountUSD,
            planMonthlyUSD: planMonthlyUSD,
            valueMultiple: valueMultiple,
            confidence: cost.confidence,
            hasUnpricedTokens: cost.hasUnpricedTokens,
            models: models
        )
    }

    private static func modelValues(
        for snapshot: ProviderSnapshot,
        pricing: PricingEngine,
        now: Date
    ) -> [MaxxerModelValue] {
        guard let days = snapshot.dailyModelUsage,
              let month = Calendar.current.dateInterval(of: .month, for: now) else { return [] }
        let models = UsageAggregation.sumModels(days.compactMap { day, models in
            day >= month.start && day <= now ? models : nil
        })
        return models.compactMap { model, tokens in
            guard let total = tokens.totalTokens, total > 0 else { return nil }
            return MaxxerModelValue(model: model, totalTokens: total,
                                    apiEquivalentUSD: pricing.cost(model: model, tokens: tokens))
        }.sorted { lhs, rhs in
            switch (lhs.apiEquivalentUSD, rhs.apiEquivalentUSD) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.model < rhs.model
            }
        }
    }

    private static func modelCost(_ models: [MaxxerModelValue]) -> APIEquivalentCost {
        let priced = models.compactMap(\.apiEquivalentUSD)
        return APIEquivalentCost(
            amountUSD: models.isEmpty ? 0 : sumOrNil(priced),
            confidence: !models.isEmpty && priced.isEmpty ? .unavailable : .estimated,
            hasUnpricedTokens: models.contains { $0.apiEquivalentUSD == nil }
        )
    }

    private static func apiEquivalentCost(
        for snapshot: ProviderSnapshot,
        pricing: PricingEngine,
        now: Date
    ) -> APIEquivalentCost {
        guard let tokens = snapshot.monthUsage,
              tokens.confidence != .unavailable,
              let totalTokens = tokens.totalTokens else {
            return APIEquivalentCost(confidence: .unavailable, hasUnpricedTokens: false)
        }

        guard let model = referenceModel(for: snapshot.providerID),
              let rollingAmountUSD = pricing.cost(model: model, tokens: tokens) else {
            return APIEquivalentCost(
                confidence: .unavailable,
                hasUnpricedTokens: totalTokens > 0
            )
        }

        let monthToDate = monthToDateAdjustment(
            snapshot: snapshot,
            rollingTokenTotal: totalTokens,
            now: now
        )
        guard monthToDate.hasPricedCoverage else {
            return APIEquivalentCost(confidence: .unavailable, hasUnpricedTokens: true)
        }

        return APIEquivalentCost(
            amountUSD: rollingAmountUSD * monthToDate.scale,
            confidence: .estimated,
            hasUnpricedTokens: monthToDate.hasUnpricedTokens
        )
    }

    private static func monthToDateAdjustment(
        snapshot: ProviderSnapshot,
        rollingTokenTotal: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> (scale: Double, hasPricedCoverage: Bool, hasUnpricedTokens: Bool) {
        // Snapshots retain token-field detail for the rolling month but only a
        // scalar per calendar day. Scale the detailed price by the MTD token
        // fraction so prior-month days cannot inflate the scorecard.
        guard let dailyTotals = snapshot.dailyTotals,
              let month = calendar.dateInterval(of: .month, for: now) else {
            return (1, true, false)
        }

        let monthToDateTokens = dailyTotals.reduce(into: 0) { total, entry in
            guard entry.key >= month.start, entry.key <= now else { return }
            total += max(entry.value, 0)
        }
        guard rollingTokenTotal > 0 else {
            return monthToDateTokens == 0 ? (1, true, false) : (0, false, true)
        }

        let hasUnpricedTokens = monthToDateTokens > rollingTokenTotal
        let scale = min(Double(monthToDateTokens) / Double(rollingTokenTotal), 1)
        return (scale, true, hasUnpricedTokens)
    }

    private static func referenceModel(for providerID: ProviderID) -> String? {
        // Legacy snapshots and providers without model detail keep their existing
        // reference baseline; heterogeneous providers remain visibly unpriced.
        switch providerID {
        case .claudeCode:
            return "claude-sonnet-4-6"
        case .codex:
            return "gpt-5"
        case .cursor:
            return "cursor-composer"
        case .antigravity, .cline, .opencode, .gemini, .copilot:
            return nil
        }
    }

    private static func sumOrNil(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +)
    }

    private static func tier(for multiple: Double) -> MaxxerTier {
        switch multiple {
        case ..<0.25:
            return .idle
        case ..<1:
            return .warming
        case ..<2:
            return .breakEven
        case ..<5:
            return .maxxing
        default:
            return .goblinMode
        }
    }
}
