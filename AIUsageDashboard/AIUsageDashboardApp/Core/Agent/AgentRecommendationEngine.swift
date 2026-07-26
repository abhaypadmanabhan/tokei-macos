import Foundation

/// Computes the agent routing hint (`AgentRecommendation`) from the utilization
/// spine. Pure and clock-injected, so it is deterministic and unit-testable.
///
/// This is the same *idea* as the human-facing "Route work here" chip
/// (`MaxxerMath.routeTarget`, issue #37) — route to the least-utilized provider — but
/// it is NOT a faithful port: the chip also requires a >=15-point spread between the
/// tightest and least-filled provider before it suggests anything, while this engine
/// uses only the issue's own flat 85%-avoid rule with no spread gate. `MaxxerMath`
/// lives under `UI/MenuBar/` and isn't compiled into the Core framework, so it can't be
/// called here regardless. A third, independent least-filled-provider heuristic also
/// exists at `DashboardView.routeTargetProviderID` (no threshold at all).
/// FOLLOW-UP: reconcile all three into one canonical policy once `MaxxerMath` moves
/// into Core — that requires picking a single rule, not just deleting a duplicate.
public enum AgentRecommendationEngine {
    /// At or above this utilization, a provider is one to avoid. The issue's own
    /// steering guidance is "avoid providers above 85% utilization".
    public static let avoidThreshold: Double = 85

    /// Build a recommendation from live utilizations, or `nil` when there is nothing
    /// worth saying (fewer than two readings and nothing to avoid).
    ///
    /// - `routeTo` is the least-utilized provider, returned only when at least two
    ///   providers reported usable quota and the least one is below the avoid
    ///   threshold. No minimum spread is required (unlike the UI chip — see the type
    ///   doc above), so this can suggest a target even when providers are close together.
    /// - `avoid` lists every provider at/over the avoid threshold, tightest first.
    public static func recommend(
        from utilizations: [Utilization],
        displayNames: [ProviderID: String],
        now: Date
    ) -> AgentRecommendation? {
        // Peak (tightest) window per provider — the reading that governs routing.
        let peakByProvider: [ProviderID: Utilization] = Dictionary(
            grouping: utilizations, by: \.providerID
        ).compactMapValues { $0.max(by: { $0.usedPercent < $1.usedPercent }) }

        guard !peakByProvider.isEmpty else { return nil }

        // Stable provider order for deterministic tie-breaks (first-seen wins).
        let ordered = ProviderID.allCases.compactMap { id in peakByProvider[id].map { (id, $0) } }

        let avoided = ordered
            .filter { $0.1.usedPercent >= avoidThreshold }
            .sorted { $0.1.usedPercent > $1.1.usedPercent }

        let leastFilled = ordered.min { lhs, rhs in
            lhs.1.usedPercent < rhs.1.usedPercent
        }

        // Suggest a target only with ≥2 readings and a genuinely-open least-filled one.
        let routeTarget: (ProviderID, Utilization)?
        if ordered.count >= 2,
           let least = leastFilled,
           least.1.usedPercent < avoidThreshold {
            routeTarget = least
        } else {
            routeTarget = nil
        }

        if routeTarget == nil, avoided.isEmpty { return nil }

        let reason = buildReason(
            avoided: avoided,
            routeTarget: routeTarget,
            displayNames: displayNames,
            now: now
        )

        return AgentRecommendation(
            routeTo: routeTarget?.0.rawValue,
            avoid: avoided.map { $0.0.rawValue },
            reason: reason
        )
    }

    // MARK: - Reason string

    private static func buildReason(
        avoided: [(ProviderID, Utilization)],
        routeTarget: (ProviderID, Utilization)?,
        displayNames: [ProviderID: String],
        now: Date
    ) -> String {
        var clauses: [String] = []

        for (id, util) in avoided {
            let name = displayNames[id] ?? id.rawValue
            var clause = "\(name) \(util.window.rawValue) \(percent(util.usedPercent))% used"
            if let resetAt = util.resetAt, let delta = resetDelta(from: now, to: resetAt) {
                clause += ", resets in \(delta)"
            }
            clauses.append(clause)
        }

        if let (id, util) = routeTarget {
            let name = displayNames[id] ?? id.rawValue
            clauses.append("route to \(name) (tightest window \(percent(util.usedPercent))%)")
        }

        return clauses.isEmpty ? "No provider is near its limit." : clauses.joined(separator: "; ")
    }

    private static func percent(_ value: Double) -> Int { Int(value.rounded()) }

    /// Compact "3h" / "12m" / "<1m" for a future reset; nil when already elapsed.
    private static func resetDelta(from now: Date, to resetAt: Date) -> String? {
        let seconds = resetAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return AgentSnapshot.compactDuration(seconds)
    }
}
