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

    /// Confidences a *routing target* may be drawn from. Everything else is a number
    /// we inferred rather than one the provider confirmed.
    ///
    /// Why this gate exists: on 2026-07-27 Claude's only window was an hour-old cached
    /// 0% (served during a 429 cooldown, `.estimated`) while Codex reported an official
    /// 75%. Ranking on `usedPercent` alone sent fan-out work to the provider nobody had
    /// real numbers for. **A stale 0% is absence of data, not free quota** — so an
    /// untrusted reading can never be evidence of headroom.
    public static let routableConfidences: Set<MetricConfidence> = [.exact, .providerReported]

    /// How old a reading may be and still be routed to. Deliberately generous — well past
    /// `ClaudeUsageClientImpl.freshCacheInterval` (10 min), so normal cache hits stay
    /// routable — because this is a backstop, not the primary gate. Nothing in the codebase
    /// *forces* a client to downgrade confidence when it serves cached data (each one does
    /// it by hand), so this catches an officially-labelled reading that is simply old.
    /// A `nil` `observedAt` means "age unknown", which is not the same as "old" and does
    /// not block routing.
    public static let maxRoutableAge: TimeInterval = 30 * 60

    /// Build a recommendation from live utilizations, or `nil` when there is nothing
    /// worth saying (fewer than two readings and nothing to avoid).
    ///
    /// - `routeTo` is the least-utilized provider **among those with a trusted reading**
    ///   (see `routableConfidences`), returned only when at least two such providers
    ///   reported usable quota and the least one is below the avoid threshold. No minimum
    ///   spread is required (unlike the UI chip — see the type doc above), so this can
    ///   suggest a target even when providers are close together.
    /// - `avoid` lists every provider at/over the avoid threshold, tightest first —
    ///   computed from *all* readings, trusted or not (see the note at `routableConfidences`).
    public static func recommend(
        from utilizations: [Utilization],
        displayNames: [ProviderID: String],
        now: Date
    ) -> AgentRecommendation? {
        // Peak (tightest) window per provider — the reading that governs routing.
        //
        // Peak is taken BEFORE the trust gate below, and that order is deliberate: if a
        // provider's tightest window is one we don't trust, the provider is not routable
        // even when some looser window of its own is confirmed. Gating first and peaking
        // after would route on a comfortable weekly number while the session window — the
        // one about to run out — is an unknown.
        let peakByProvider: [ProviderID: Utilization] = Dictionary(
            grouping: utilizations, by: \.providerID
        ).compactMapValues { $0.max(by: { $0.usedPercent < $1.usedPercent }) }

        guard !peakByProvider.isEmpty else { return nil }

        // Stable provider order for deterministic tie-breaks (first-seen wins).
        let ordered = ProviderID.allCases.compactMap { id in peakByProvider[id].map { (id, $0) } }

        // Deliberately asymmetric. `avoid` is computed from *every* reading: an untrusted
        // number is not evidence of headroom, but a high one is still evidence of pressure,
        // and the safe failure mode is steering away from a provider we're unsure about.
        let avoided = ordered
            .filter { $0.1.usedPercent >= avoidThreshold }
            .sorted { $0.1.usedPercent > $1.1.usedPercent }

        // `routeTo`, by contrast, may only be drawn from confirmed, recent readings.
        let trusted = ordered.filter { isRoutable($0.1, now: now) }

        let leastFilled = trusted.min { lhs, rhs in
            lhs.1.usedPercent < rhs.1.usedPercent
        }

        // Suggest a target only with ≥2 *trusted* readings and a genuinely-open least-filled
        // one. Comparing "least utilized" across providers is only meaningful between numbers
        // we actually have; one trusted reading has nothing to be least of.
        let routeTarget: (ProviderID, Utilization)?
        if trusted.count >= 2,
           let least = leastFilled,
           least.1.usedPercent < avoidThreshold {
            routeTarget = least
        } else {
            routeTarget = nil
        }

        // Providers held back from routing, minus any already named in `avoid` (naming them
        // twice is noise). Surfaced so the omission is visible — a silently-dropped provider
        // reads as "considered and rejected on the numbers", which is a different claim.
        let avoidedIDs = Set(avoided.map(\.0))
        let excluded = ordered.filter { !isRoutable($0.1, now: now) && !avoidedIDs.contains($0.0) }

        if routeTarget == nil, avoided.isEmpty, excluded.isEmpty { return nil }

        let reason = buildReason(
            avoided: avoided,
            excluded: excluded,
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

    /// Whether a reading may be used as evidence of *headroom* — confirmed by the provider
    /// and not known to be old. Note this is only ever used to gate `routeTo`; `avoid`
    /// intentionally considers every reading (see `recommend`).
    private static func isRoutable(_ utilization: Utilization, now: Date) -> Bool {
        guard routableConfidences.contains(utilization.confidence) else { return false }
        guard let observedAt = utilization.observedAt else { return true } // age unknown ≠ old
        return now.timeIntervalSince(observedAt) <= maxRoutableAge
    }

    // MARK: - Reason string

    private static func buildReason(
        avoided: [(ProviderID, Utilization)],
        excluded: [(ProviderID, Utilization)],
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

        for (id, util) in excluded {
            let name = displayNames[id] ?? id.rawValue
            clauses.append("\(name) excluded from routing (\(exclusionCause(util, now: now)))")
        }

        if let (id, util) = routeTarget {
            let name = displayNames[id] ?? id.rawValue
            clauses.append("route to \(name) (tightest window \(percent(util.usedPercent))%)")
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
            let age = AgentSnapshot.compactDuration(max(0, now.timeIntervalSince(observedAt)))
            return "reading is \(age) old"
        }
    }

    private static func percent(_ value: Double) -> Int { Int(value.rounded()) }

    /// Compact "3h" / "12m" / "<1m" for a future reset; nil when already elapsed.
    private static func resetDelta(from now: Date, to resetAt: Date) -> String? {
        let seconds = resetAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return AgentSnapshot.compactDuration(seconds)
    }
}
