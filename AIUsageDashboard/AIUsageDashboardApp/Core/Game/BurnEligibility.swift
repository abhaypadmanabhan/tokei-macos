import Foundation

/// The shared plan-provider boundary for every burn calculation (patch bible §7).
/// An explicit plan set replaces the subscription-product fallback, even when those
/// configured providers are hidden or absent from the current snapshots.
public struct BurnEligibility: Sendable {
    public let providers: Set<ProviderID>
    public let monthlyPlanUSD: [ProviderID: Double]

    public init(monthlyPlanUSD: [ProviderID: Double]) {
        let plans = monthlyPlanUSD.filter { $0.value.isFinite && $0.value > 0 }
        self.monthlyPlanUSD = plans
        providers = plans.isEmpty ? [.claudeCode, .codex, .cursor, .antigravity, .copilot] : Set(plans.keys)
    }
}
