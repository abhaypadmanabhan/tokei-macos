import Foundation

/// Computes the agent routing hint (`AgentRecommendation`) from the utilization
/// spine. Pure and clock-injected, so it is deterministic and unit-testable.
///
/// The decision itself is **not made here**. "Which provider should work go to" has
/// exactly one implementation — `RouteTargetPolicy` in this same directory — and this
/// engine is the machine-facing caller of it, using `RouteTargetPolicy.agent`
/// (85% avoid line, no spread gate, no extra ceiling). The human-facing surfaces
/// (`MaxxerMath.routeTarget` → the "route work here" chip, `OverviewView`'s headroom
/// dot and `DashboardView`'s drill-in chip) call the same type with
/// `RouteTargetPolicy.human`, which adds a ≥15-point spread gate and a stricter 70%
/// ceiling so a chip does not nag over a 2-point difference. Same rule, two tunings —
/// read `RouteTargetPolicy`'s doc comment for the rule and the invariants behind it.
///
/// What remains this engine's own job: turning that decision into the public
/// `AgentRecommendation` schema and writing the human-readable `reason` string,
/// including projecting the already-selected provider headline account as structured data.
public enum AgentRecommendationEngine {
    /// The single policy this engine routes on. Exposed so callers and tests can read
    /// the thresholds without duplicating them.
    public static let policy: RouteTargetPolicy = .agent

    /// Build a recommendation from live utilizations, or `nil` when there is nothing
    /// worth saying (fewer than two readings and nothing to avoid).
    ///
    /// - Parameters:
    ///   - utilizations: every live reading across providers.
    ///   - displayNames: provider id → human name, for the `reason` string.
    ///   - providers: public provider projections carrying the canonical headline account.
    ///   - now: current instant, injected for determinism.
    ///
    /// Routing semantics — `routeTo` from trusted readings only, `avoid` from every
    /// reading — live in `RouteTargetPolicy`.
    public static func recommend(
        from utilizations: [Utilization],
        displayNames: [ProviderID: String],
        providers: [AgentProvider] = [],
        now: Date
    ) -> AgentRecommendation? {
        let decision = policy.evaluate(utilizations, now: now)
        guard !decision.hasNothingToSay else { return nil }

        let targetProvider = decision.routeTo.flatMap { utilization in
            providers.first { $0.id == utilization.providerID.rawValue }
        }
        let targetAccount: AgentAccount? = targetProvider.flatMap { provider in
            guard let headlineAccountID = provider.headlineAccountID else { return nil }
            return provider.accounts?.first { $0.accountID == headlineAccountID }
        }
        // An executable account target requires a verified selector. Provider-only `routeTo`
        // remains for legacy/single-account sources that cannot publish one safely.
        let target = targetAccount.flatMap { account -> AgentRecommendationTarget? in
            guard let providerID = decision.routeTo?.providerID.rawValue,
                  let accountID = account.accountID,
                  let selector = account.selector?.executable(forProvider: providerID) else { return nil }
            return AgentRecommendationTarget(
                provider: providerID,
                accountID: accountID,
                selector: selector
            )
        }
        let avoidedAccounts = providers.flatMap { provider in
            (provider.accounts ?? []).compactMap { account -> AgentAccountReference? in
                guard let usedPercent = account.quota?.usedPercent,
                      usedPercent >= policy.avoidThreshold,
                      let accountID = account.accountID else { return nil }
                return AgentAccountReference(provider: provider.id, accountID: accountID)
            }
        }.sorted {
            ($0.provider, $0.accountID) < ($1.provider, $1.accountID)
        }

        let reason = buildReason(
            decision: decision,
            displayNames: displayNames,
            targetProvider: targetProvider,
            targetAccount: targetAccount,
            now: now
        )
        let validUntil = targetAccount?.quota?.validUntil
            ?? recommendationValidity(for: decision.routeTo, now: now)

        return AgentRecommendation(
            routeTo: decision.routeTo?.providerID.rawValue,
            avoid: decision.avoid.map(\.providerID.rawValue),
            reason: reason,
            target: target,
            avoidAccounts: providers.isEmpty ? nil : avoidedAccounts,
            validUntil: validUntil
        )
    }

    private static func recommendationValidity(
        for target: Utilization?,
        now: Date
    ) -> Date? {
        guard let target else { return nil }
        let candidates = [
            now.addingTimeInterval(AgentSnapshot.stalenessThreshold),
            target.observedAt?.addingTimeInterval(policy.maxRoutableAge),
            target.resetAt.flatMap { $0 > now ? $0 : nil }
        ].compactMap { $0 }
        return candidates.min()
    }

    // MARK: - Reason string

    private static func buildReason(
        decision: RouteDecision,
        displayNames: [ProviderID: String],
        targetProvider: AgentProvider?,
        targetAccount: AgentAccount?,
        now: Date
    ) -> String {
        var clauses: [String] = []

        for util in decision.avoid {
            let name = displayName(util.providerID, displayNames)
            var clause = "\(name) \(util.window.rawValue) \(percent(util.usedPercent))% used"
            if let resetAt = util.resetAt, let delta = resetDelta(from: now, to: resetAt) {
                clause += ", resets in \(delta)"
            }
            clauses.append(clause)
        }

        for util in decision.excluded {
            let name = displayName(util.providerID, displayNames)
            clauses.append("\(name) excluded from routing (\(exclusionCause(util, now: now)))")
        }

        if let target = decision.routeTo {
            let name = displayName(target.providerID, displayNames)
            let accountClause = (targetProvider?.accounts?.count ?? 0) > 1
                ? targetAccount.map { " account \($0.label)" } ?? ""
                : ""
            let clause = "route to \(name)\(accountClause) (tightest window \(percent(target.usedPercent))%)"
            clauses.append(clause)
        }

        return clauses.isEmpty ? "No provider is near its limit." : clauses.joined(separator: "; ")
    }

    /// Why a provider was held back from routing. The two causes are distinct and a reader
    /// needs to tell them apart: an unconfirmed number vs. a confirmed but outdated one.
    /// Confidence wording matches the public `AgentWindow.confidence` vocabulary so the
    /// reason string and the window a reader is looking at use the same words.
    private static func exclusionCause(_ utilization: Utilization, now: Date) -> String {
        switch utilization.confidence {
        case .localParsed, .estimated:
            return "local estimate, not a confirmed reading"
        case .unavailable:
            return "no reading available"
        case .exact, .providerReported:
            guard let observedAt = utilization.observedAt else { return "not a confirmed reading" }
            let seconds = now.timeIntervalSince(observedAt)
            // A future stamp is a clock problem, not an age. Saying "0s old" about a
            // reading we just refused to route to would read as a contradiction.
            guard seconds >= 0 else { return "reading is timestamped in the future" }
            return "reading is \(AgentSnapshot.compactDuration(seconds)) old"
        }
    }

    private static func displayName(_ id: ProviderID, _ names: [ProviderID: String]) -> String {
        names[id] ?? id.rawValue
    }

    private static func percent(_ value: Double) -> Int { Int(value.rounded()) }

    /// Compact "3h" / "12m" / "<1m" for a future reset; nil when already elapsed.
    private static func resetDelta(from now: Date, to resetAt: Date) -> String? {
        let seconds = resetAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return AgentSnapshot.compactDuration(seconds)
    }
}
