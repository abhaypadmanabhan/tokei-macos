import Foundation

/// **The one answer to "which provider should new work go to?"**
///
/// Before this type there were three independent implementations — the agent
/// engine (`AgentRecommendationEngine.recommend`), the human-facing "route work
/// here" chip (`MaxxerMath.routeTarget`, issue #37) and the dashboard's route dot
/// (`DashboardView.routeTargetProviderID` / `OverviewView.headroomProviderID`) —
/// which disagreed on the threshold and, worse, disagreed on whether the reading
/// had to be *trusted* at all. Only the agent path was trust-gated (`f725bac`), so
/// both UI surfaces could still point a human at a stale `local_estimate`: the exact
/// bug `f725bac` fixed for agents. All four sites now delegate here.
///
/// ## The canonical rule
///
/// 1. **Peak first.** Reduce each provider to its *tightest* (highest-used) window.
///    That single reading represents the provider.
/// 2. **Then gate on trust.** A peak may be a route target only if its confidence is
///    in `routableConfidences` and it is not older than `maxRoutableAge`.
/// 3. **Route to the least-filled trusted peak**, but only when
///    - at least `minTrustedProviders` distinct providers have a trusted peak
///      (least-utilized is only meaningful between numbers we actually have), and
///    - that peak is below `avoidThreshold` and within `maxRouteTargetPercent`, and
///    - it is at least `minSpread` points emptier than the tightest peak anywhere.
/// 4. **Avoid every peak at/over `avoidThreshold`**, trusted or not.
///
/// ## Why the rule is shaped this way (the invariants, not preferences)
///
/// - **Peak-then-gate ordering is deliberate.** Gating first and peaking after would
///   route on a provider's comfortable *weekly* number while its *session* window —
///   the one about to run out — is an unknown. A provider whose tightest window is
///   untrusted is not routable, even if some looser window of its own is confirmed.
/// - **The avoid/routeTo asymmetry is deliberate.** `avoid` reads *every* peak;
///   `routeTo` only *trusted* peaks. An untrusted number is not evidence of headroom
///   (a stale 0% is absence of data, not free quota) but a high one is still evidence
///   of pressure, and steering away from a provider we are unsure about is the safe
///   failure mode. Do not collapse these into one filter.
/// - **The spread gate stayed a parameter, not a rule.** `minSpread` (15 points in
///   `.human`) exists so the chip does not nag a human over a 2-point difference. It is a
///   *presentation* choice and must never become the agent rule — an agent asking
///   "where should this run" wants the best available answer even when the field is
///   tight, so `.agent` sets it to 0. Same for `maxRouteTargetPercent`: the UI holds a
///   stricter 70% bar than the 85% avoid line because a chip is a recommendation,
///   while `nil` on `.agent` keeps the agent path on the issue's own flat 85% rule.
/// - **`minSpread` measures against the tightest peak among *all* readings**, not just
///   trusted ones — same reasoning as `avoid`. The question the gate asks is "is there
///   meaningfully more room here than where I am feeling pressure", and pressure is
///   evidence from every reading.
///
/// Pure and clock-injected: same inputs, same output, always.
public struct RouteTargetPolicy: Sendable, Equatable {
    /// Confidences a *routing target* may be drawn from. Everything else is a number
    /// we inferred rather than one the provider confirmed.
    ///
    /// Why this gate exists: on 2026-07-27 Claude's only window was an hour-old cached
    /// 0% (served during a 429 cooldown, `.estimated`) while Codex reported an official
    /// 75%. Ranking on `usedPercent` alone sent fan-out work to the provider nobody had
    /// real numbers for. **A stale 0% is absence of data, not free quota.**
    public var routableConfidences: Set<MetricConfidence>

    /// How old a reading may be and still be routed to. Deliberately generous — well past
    /// `ClaudeUsageClientImpl.freshCacheInterval` (10 min), so normal cache hits stay
    /// routable — because this is a backstop, not the primary gate. Nothing in the codebase
    /// *forces* a client to downgrade confidence when it serves cached data (each one does
    /// it by hand), so this catches an officially-labelled reading that is simply old.
    /// A `nil` `observedAt` means "age unknown", which is not the same as "old" and does
    /// not block routing. A *future-dated* `observedAt` is a different case again — see
    /// `maxClockSkew`.
    public var maxRoutableAge: TimeInterval

    /// How far **ahead** of our clock a reading may be stamped and still be judged on its
    /// age. Beyond this it is treated as untrustworthy, not as fresh.
    ///
    /// Zero tolerance would be wrong: `observedAt` is stamped from a provider's clock, and
    /// two NTP-synced machines still disagree by a second or so, plus timestamps get
    /// rounded on the way through an API. Rejecting a reading a second into the future
    /// would drop good data for no safety gain. 60s absorbs that benign jitter.
    ///
    /// Past the tolerance the two clocks disagree by more than jitter explains, so
    /// `now - observedAt` is no longer a meaningful age and the gate built on it means
    /// nothing. Crucially, an unclamped age check *fails open*: a reading dated ahead of
    /// the clock is never "older than `maxRoutableAge`", so a provider stamping a skewed
    /// or wrong-timezone timestamp would stay routable **forever** — the exact failure
    /// the age gate exists to prevent. A trust gate must fail closed, so a materially
    /// future-dated reading is not routable.
    public static let maxClockSkew: TimeInterval = 60

    /// At or above this utilization a provider is one to avoid, and can never be a route
    /// target. The issue's own steering guidance is "avoid providers above 85%".
    public var avoidThreshold: Double

    /// An optional, stricter inclusive ceiling for a *route target* only (the UI's 70%).
    /// `nil` means `avoidThreshold` is the only bar. Purely a presentation tier: it makes
    /// a surface quieter, it never makes a provider "safe".
    public var maxRouteTargetPercent: Double?

    /// Minimum gap, in percentage points, between the tightest peak anywhere and the
    /// candidate target. 0 disables the gate.
    public var minSpread: Double

    /// How many distinct providers must have a *trusted* peak before a target is named.
    /// Two, because "least utilized" needs something to be least of.
    public var minTrustedProviders: Int

    public init(
        routableConfidences: Set<MetricConfidence> = [.exact, .providerReported],
        maxRoutableAge: TimeInterval = 30 * 60,
        avoidThreshold: Double = 85,
        maxRouteTargetPercent: Double? = nil,
        minSpread: Double = 0,
        minTrustedProviders: Int = 2
    ) {
        self.routableConfidences = routableConfidences
        self.maxRoutableAge = maxRoutableAge
        self.avoidThreshold = avoidThreshold
        self.maxRouteTargetPercent = maxRouteTargetPercent
        self.minSpread = minSpread
        self.minTrustedProviders = minTrustedProviders
    }

    /// The machine-facing tuning: no spread gate, no extra ceiling. An agent wants the
    /// best available answer even when providers are close together.
    public static let agent = RouteTargetPolicy()

    /// The human-facing tuning: a suggestion has to be worth interrupting for, so it
    /// needs a ≥15-point spread and a target with real headroom (≤70%).
    ///
    /// Named `human` rather than `ui` to pair with `agent` by *who is reading the
    /// answer*, which is the only thing that differs between the two.
    public static let human = RouteTargetPolicy(
        maxRouteTargetPercent: 70,
        minSpread: 15
    )

    // MARK: - Evaluation

    /// Apply the policy to a set of live readings.
    ///
    /// - Parameters:
    ///   - utilizations: every live reading; grouped into per-provider peaks internally.
    ///     Callers that hide providers (the UI) filter *before* calling — this type has
    ///     no opinion on visibility.
    ///   - now: current instant, injected so the age gate is deterministic.
    public func evaluate(_ utilizations: [Utilization], now: Date) -> RouteDecision {
        let peaks = Self.peaks(in: utilizations)
        guard !peaks.isEmpty else { return .empty }

        // Step 4 — computed from EVERY peak, trusted or not (see the asymmetry note).
        let avoided = peaks
            .filter { $0.usedPercent >= avoidThreshold }
            .sorted { $0.usedPercent > $1.usedPercent }

        // Step 2 — the trust gate applies only to routing candidates.
        let trusted = peaks.filter { isRoutable($0, now: now) }

        // Step 3.
        let routeTo = routeTarget(trusted: trusted, peaks: peaks)

        // Providers held back from routing, minus any already named in `avoid` (naming
        // them twice is noise). Surfaced so the omission is visible — a silently-dropped
        // provider reads as "considered and rejected on the numbers", a different claim.
        let avoidedIDs = Set(avoided.map(\.providerID))
        let excluded = peaks.filter {
            !isRoutable($0, now: now) && !avoidedIDs.contains($0.providerID)
        }

        return RouteDecision(routeTo: routeTo, avoid: avoided, excluded: excluded, peaks: peaks)
    }

    /// Just the target — the shape the UI surfaces need.
    public func routeTarget(in utilizations: [Utilization], now: Date) -> Utilization? {
        evaluate(utilizations, now: now).routeTo
    }

    /// Whether a reading may be used as evidence of *headroom* — confirmed by the
    /// provider, not known to be old, and not stamped in the future. Only ever gates
    /// `routeTo`; `avoid` intentionally considers every reading.
    public func isRoutable(_ utilization: Utilization, now: Date) -> Bool {
        guard routableConfidences.contains(utilization.confidence) else { return false }
        guard let observedAt = utilization.observedAt else { return true } // age unknown ≠ old
        let age = now.timeIntervalSince(observedAt)
        // Negative age = stamped ahead of our clock. Past the jitter tolerance that is a
        // broken clock, not a fresh reading — and it would otherwise pass the age check
        // forever (see `maxClockSkew`).
        guard age >= -Self.maxClockSkew else { return false }
        return age <= maxRoutableAge
    }

    /// Each provider reduced to its tightest (highest-used) window, in a stable
    /// `ProviderID.allCases` order so ties break deterministically and no surface
    /// flickers between equals.
    public static func peaks(in utilizations: [Utilization]) -> [Utilization] {
        let byProvider: [ProviderID: Utilization] = Dictionary(
            grouping: utilizations, by: \.providerID
        ).compactMapValues { $0.max(by: { $0.usedPercent < $1.usedPercent }) }
        return ProviderID.allCases.compactMap { byProvider[$0] }
    }

    private func routeTarget(trusted: [Utilization], peaks: [Utilization]) -> Utilization? {
        guard trusted.count >= minTrustedProviders,
              let least = trusted.min(by: { $0.usedPercent < $1.usedPercent }),
              let tightest = peaks.max(by: { $0.usedPercent < $1.usedPercent }),
              least.usedPercent < avoidThreshold,
              tightest.usedPercent - least.usedPercent >= minSpread
        else { return nil }

        if let ceiling = maxRouteTargetPercent, least.usedPercent > ceiling { return nil }
        return least
    }
}

/// The outcome of applying a `RouteTargetPolicy` — everything a caller needs to both
/// act on the decision and explain it.
public struct RouteDecision: Sendable, Equatable {
    /// The peak reading of the provider to route to, or `nil` when the honest answer
    /// is "not enough trusted signal to say".
    public let routeTo: Utilization?
    /// Peaks at/over `avoidThreshold`, tightest first — from *all* readings.
    public let avoid: [Utilization]
    /// Peaks held back from routing by the trust gate, excluding those already in
    /// `avoid`. Surfaced so the omission can be explained rather than looking like a
    /// judgement on the numbers.
    public let excluded: [Utilization]
    /// Every provider's peak, in stable provider order.
    public let peaks: [Utilization]

    public static let empty = RouteDecision(routeTo: nil, avoid: [], excluded: [], peaks: [])

    /// Nothing worth saying — no target, nothing to avoid, nothing withheld.
    public var hasNothingToSay: Bool { routeTo == nil && avoid.isEmpty && excluded.isEmpty }

    public init(
        routeTo: Utilization?,
        avoid: [Utilization],
        excluded: [Utilization],
        peaks: [Utilization]
    ) {
        self.routeTo = routeTo
        self.avoid = avoid
        self.excluded = excluded
        self.peaks = peaks
    }
}
