// SHIM — deleted at integration when WP-1 core lands (Bible §2 step 3).
//
// The types below are the FROZEN Maxxer contract from Patch Bible 2026-07-19 §4,
// reproduced VERBATIM so the Value surface (WP-2) can be built and reviewed before
// `Core/Maxxer/` (WP-1) merges. They are declared here only to make this branch
// compile on its own; WP-1's real implementations replace them 1:1 and this entire
// file is deleted at merge — nothing outside it may add a member to these types.
//
// What is REAL here and what is not:
//   · `MaxxerPlanCostStore` is the real implementation (UserDefaults, contract-exact).
//     Plan costs the user types in Settings are genuinely persisted today.
//   · `MaxxerValueEngine.scorecard` is a STUB. It reads real snapshots and real plan
//     costs, but prices tokens at a single flat blended rate instead of routing them
//     through `PricingEngine` per model — because a per-model token split does not
//     exist at the snapshot level, which is precisely the gap WP-1 closes. Every
//     dollar value it produces is therefore `.estimated` at best and must never be
//     presented as exact.

import Foundation
import AIUsageDashboardCore

// MARK: - Frozen contract (Bible §4 — verbatim, do not edit)

public struct MaxxerProviderValue: Sendable, Equatable {
    public let providerID: String
    public let apiEquivalentUSD: Double?   // month-to-date, nil if unpriceable
    public let planMonthlyUSD: Double?     // nil = user has not configured
    public let valueMultiple: Double?      // apiEquivalentUSD / planMonthlyUSD; nil unless both known
    public let confidence: MetricConfidence
    public let hasUnpricedTokens: Bool
}

public enum MaxxerTier: String, CaseIterable, Sendable {
    case idle        // total multiple < 0.25
    case warming     // 0.25 ..< 1
    case breakEven   // 1 ..< 2
    case maxxing     // 2 ..< 5
    case goblinMode  // >= 5
}

public struct MaxxerScorecard: Sendable, Equatable {
    public let providers: [MaxxerProviderValue]
    public let totalAPIEquivalentUSD: Double?
    public let totalPlanUSD: Double?
    public let totalValueMultiple: Double?
    public let tier: MaxxerTier?           // nil when no multiple computable
}

public final class MaxxerPlanCostStore {
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func monthlyUSD(for providerID: String) -> Double? {
        // `object(forKey:)` first: `double(forKey:)` alone cannot distinguish an
        // unset key from a stored 0, and "unset" must never read as "$0 plan".
        guard let stored = defaults.object(forKey: Self.key(providerID)) as? Double else { return nil }
        return stored
    }

    public func setMonthlyUSD(_ amount: Double?, for providerID: String) {
        if let amount {
            defaults.set(amount, forKey: Self.key(providerID))
        } else {
            defaults.removeObject(forKey: Self.key(providerID))
        }
    }

    private let defaults: UserDefaults

    private static func key(_ providerID: String) -> String { "maxxer.planCost.\(providerID)" }
}

public enum MaxxerValueEngine {
    public static func scorecard(
        snapshots: [ProviderSnapshot],
        planCosts: MaxxerPlanCostStore,
        now: Date
    ) -> MaxxerScorecard {
        let providers = snapshots.map { snapshot -> MaxxerProviderValue in
            let plan = planCosts.monthlyUSD(for: snapshot.providerID.rawValue)
            let monthTokens = snapshot.monthUsage?.totalTokens
            let confidence = ShimPricing.confidence(for: snapshot)
            let apiEquivalent = ShimPricing.blendedUSD(tokens: monthTokens, confidence: confidence)

            return MaxxerProviderValue(
                providerID: snapshot.providerID.rawValue,
                apiEquivalentUSD: apiEquivalent,
                planMonthlyUSD: plan,
                valueMultiple: ShimPricing.multiple(apiEquivalentUSD: apiEquivalent, planMonthlyUSD: plan),
                confidence: confidence,
                // The stub prices every token at one rate, so it never leaves tokens
                // unpriced; WP-1 sets this per `APIEquivalentCost` semantics.
                hasUnpricedTokens: false
            )
        }

        // `.unavailable` providers contribute to neither total (Bible WP-1 AC 4):
        // an unpriceable provider is excluded, not counted as zero.
        let priced = providers.filter { $0.confidence != .unavailable }
        let totalAPI = ShimPricing.sum(priced.map(\.apiEquivalentUSD))
        let totalPlan = ShimPricing.sum(priced.map(\.planMonthlyUSD))
        let totalMultiple = ShimPricing.multiple(apiEquivalentUSD: totalAPI, planMonthlyUSD: totalPlan)

        return MaxxerScorecard(
            providers: providers,
            totalAPIEquivalentUSD: totalAPI,
            totalPlanUSD: totalPlan,
            totalValueMultiple: totalMultiple,
            tier: totalMultiple.map(ShimPricing.tier(for:))
        )
    }
}

// MARK: - Stub pricing (SHIM-only — never part of the §4 contract)

/// Deliberately a separate namespace so the frozen contract types above keep
/// exactly the members Bible §4 lists. Deleted with the rest of this file.
private enum ShimPricing {
    /// One flat blended $/token rate standing in for per-model `PricingEngine`
    /// lookup. Order-of-magnitude only: ≈$3/M in + $15/M out at a 4:1 in:out mix.
    /// WP-1 replaces this with real per-model pricing.
    static let blendedUSDPerToken = 5.4 / 1_000_000

    /// The best this stub can honestly claim. A provider with no month-to-date
    /// usage is `.unavailable`, never a confident $0.
    static func confidence(for snapshot: ProviderSnapshot) -> MetricConfidence {
        guard let month = snapshot.monthUsage, month.totalTokens != nil else { return .unavailable }
        // A flat blended rate is an estimate no matter how exact the token count is.
        return month.confidence == .unavailable ? .unavailable : .estimated
    }

    static func blendedUSD(tokens: Int?, confidence: MetricConfidence) -> Double? {
        guard confidence != .unavailable, let tokens else { return nil }
        return Double(tokens) * blendedUSDPerToken
    }

    /// `nil` unless both sides are known and the plan cost is a real positive
    /// figure — dividing by an unset or zero plan would invent an infinite multiple.
    static func multiple(apiEquivalentUSD: Double?, planMonthlyUSD: Double?) -> Double? {
        guard let api = apiEquivalentUSD, let plan = planMonthlyUSD, plan > 0 else { return nil }
        return api / plan
    }

    /// `nil` when nothing contributed, so an empty scorecard shows "—" not "$0".
    static func sum(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
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
}
