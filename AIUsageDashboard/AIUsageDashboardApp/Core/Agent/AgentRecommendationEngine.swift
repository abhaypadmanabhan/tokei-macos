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
/// `RouteTargetPolicy.ui`, which adds a ≥15-point spread gate and a stricter 70%
/// ceiling so a chip does not nag over a 2-point difference. Same rule, two tunings —
/// read `RouteTargetPolicy`'s doc comment for the rule and the invariants behind it.
///
/// What remains this engine's own job: turning that decision into the public
/// `AgentRecommendation` schema and writing the human-readable `reason` string,
/// including naming the Claude account a headline number came from so a reader knows
/// which `CLAUDE_CONFIG_DIR` to export.
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
    ///   - accounts: per-provider account breakdown (multi-account Claude), used to
    ///     name *which* account the headline reading came from. Absent or single-entry
    ///     lists add nothing to the reason.
    ///   - now: current instant, injected for determinism.
    ///
    /// Routing semantics — `routeTo` from trusted readings only, `avoid` from every
    /// reading — live in `RouteTargetPolicy`.
    public static func recommend(
        from utilizations: [Utilization],
        displayNames: [ProviderID: String],
        accounts: [ProviderID: [AgentAccount]] = [:],
        now: Date
    ) -> AgentRecommendation? {
        let decision = policy.evaluate(utilizations, now: now)
        guard !decision.hasNothingToSay else { return nil }

        let reason = buildReason(
            decision: decision,
            displayNames: displayNames,
            accounts: accounts,
            now: now
        )

        return AgentRecommendation(
            routeTo: decision.routeTo?.providerID.rawValue,
            avoid: decision.avoid.map(\.providerID.rawValue),
            reason: reason
        )
    }

    // MARK: - Reason string

    private static func buildReason(
        decision: RouteDecision,
        displayNames: [ProviderID: String],
        accounts: [ProviderID: [AgentAccount]],
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
            var clause = "route to \(name) (tightest window \(percent(target.usedPercent))%"
            if let account = headlineAccount(for: target.providerID, accounts: accounts) {
                clause += ", account \(account.label) — export CLAUDE_CONFIG_DIR=\(account.id)"
            }
            clause += ")"
            clauses.append(clause)
        }

        return clauses.isEmpty ? "No provider is near its limit." : clauses.joined(separator: "; ")
    }

    /// The account a multi-account provider's headline number came from: the one with
    /// the **most headroom** (lowest peak utilization) among accounts that reported a
    /// usable window. This deliberately mirrors
    /// `ClaudeCodeProvider.headlineQuotaWindows` — the provider picks the best account's
    /// windows as its headline quota, so naming any other account here would point the
    /// reader at a number that is not the one being recommended.
    ///
    /// `nil` for a single-account provider: with one account there is nothing to
    /// disambiguate and `CLAUDE_CONFIG_DIR` is just the default.
    private static func headlineAccount(
        for providerID: ProviderID,
        accounts: [ProviderID: [AgentAccount]]
    ) -> AgentAccount? {
        guard let providerAccounts = accounts[providerID], providerAccounts.count >= 2 else {
            return nil
        }
        return providerAccounts
            .filter { !$0.windows.isEmpty }
            .min { peakPercent($0.windows) < peakPercent($1.windows) }
    }

    private static func peakPercent(_ windows: [AgentWindow]) -> Double {
        windows.map(\.usedPercent).max() ?? 0
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
            let age = AgentSnapshot.compactDuration(max(0, now.timeIntervalSince(observedAt)))
            return "reading is \(age) old"
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
