import Foundation
import AIUsageDashboardCore

/// Pure math for the Token-Maxxer surface — the previous-period span, the
/// single tightest window across providers, lifetime token totals (#41), and the
/// value-surface number formatting (#23). No I/O, no clock, no SwiftUI: every
/// value is derived from arguments so the same inputs always yield the same
/// output, which is what makes it unit-testable from the Core test bundle even
/// though it physically lives under `UI/`.
///
/// It reads only the frozen `QuotaWindow`/`Utilization`/`ProviderSnapshot` shapes
/// — it never mutates Core state and holds no credentials (see the `Utilization`
/// security invariant).
///
/// This file is the app's ONLY `UI/` source compiled into `AIUsageDashboardCoreTests`
/// (see `project.yml`), so pure logic that the value/lifetime surfaces need
/// covered lives here rather than beside its view. It therefore may reference
/// only Foundation + `AIUsageDashboardCore` — never another app-target type.
public enum MaxxerMath {

    // MARK: - Previous-period span

    /// The span of a rolling quota window, used by the menu bar to find "the same point
    /// last period" in the quota series. `nil` for window types with no fixed span (a
    /// session, a credit balance, a per-model or lifetime total).
    ///
    /// Monthly is treated as 30 days: close enough to find last period's sample. Pace
    /// is stricter and does not guess a month — see `QuotaPace.duration(for:reported:)`.
    public static func canonicalWindowDuration(for type: QuotaWindowType) -> TimeInterval? {
        switch type {
        case .fiveHour: return 5 * 3_600
        case .daily:    return 24 * 3_600
        case .weekly:   return 7 * 86_400
        case .monthly:  return 30 * 86_400
        case .session, .credits, .perModel, .lifetime:
            return nil
        }
    }

    // MARK: - Tightest window selection

    /// The single tightest (highest-utilization) window across every provider —
    /// the number that actually constrains you. `nil` when there is no live quota
    /// anywhere. Deterministic: on a tie the first-seen reading wins (stable input
    /// order → stable pick), so the menu bar never flickers between equals.
    public static func tightestWindow(in utilizations: [Utilization]) -> Utilization? {
        utilizations.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return candidate.usedPercent > current.usedPercent ? candidate : current
        }
    }

    // MARK: - Route-here target (#37)

    /// The provider worth routing new work to — the human-facing side of the ONE
    /// canonical rule in `RouteTargetPolicy` (Core). This is a thin delegation: every
    /// threshold, the trust gate and the peak-then-gate ordering live there, so the
    /// chip, the Overview headroom dot and the agent snapshot can never disagree
    /// about what "route here" means again.
    ///
    /// `.human` is the human tuning of that rule: at least two providers with a
    /// *trusted* peak reading, a target with genuine headroom (≤70%), and a ≥15-point
    /// spread from the tightest reading anywhere — so the chip never nags over a
    /// 2-point difference. `nil` (no chip) whenever any of those fails, which now
    /// includes "the emptiest-looking provider is only a stale `local_estimate`":
    /// a stale 0% is absence of data, not free quota, and pointing a human at it is
    /// the same bug `f725bac` fixed for agents.
    ///
    /// Deterministic: each provider is reduced to its tightest window and ties break
    /// in stable `ProviderID` order, so the menu bar never flickers between equals.
    ///
    /// - Parameters:
    ///   - utilizations: live readings; the caller filters hidden providers first.
    ///   - policy: the tuning to apply. Defaults to `.human`; injectable for tests.
    ///   - now: current instant — injected, never read from the wall clock here, so
    ///     this file stays pure (the age half of the trust gate needs it).
    public static func routeTarget(
        in utilizations: [Utilization],
        policy: RouteTargetPolicy = .human,
        now: Date
    ) -> Utilization? {
        policy.routeTarget(in: utilizations, now: now)
    }

    // MARK: - Lifetime totals (#41)

    /// All-time tokens across providers, plus how much of that figure is a
    /// fallback rather than a provider-reported lifetime number.
    public struct LifetimeTotal: Sendable, Equatable {
        /// Summed all-time tokens across contributing providers.
        public let tokens: Int
        /// Worst confidence among the contributors — the headline can only be as
        /// trustworthy as its weakest input.
        public let confidence: MetricConfidence
        /// True when at least one provider had no `lifetimeUsage` and was summed
        /// from `dailyTotals` instead, so the total is a floor, not a true all-time.
        public let usedDailyFallback: Bool
        /// How many providers actually contributed a number.
        public let contributingProviders: Int

        public init(tokens: Int, confidence: MetricConfidence, usedDailyFallback: Bool, contributingProviders: Int) {
            self.tokens = tokens
            self.confidence = confidence
            self.usedDailyFallback = usedDailyFallback
            self.contributingProviders = contributingProviders
        }
    }

    /// Aggregate all-time tokens, mirroring the `.lifetime` branch of
    /// `UsageAnalytics.tokens(for:range:)` (`UsageAnalytics.swift:247`):
    /// prefer the provider's own `lifetimeUsage`, else sum its `dailyTotals`.
    ///
    /// Differs from that line in ONE deliberate way: a provider with neither
    /// source contributes *nothing* instead of `0`. Summing zeros would let
    /// Cursor/Antigravity/Gemini (which report `nil` lifetime by design) silently
    /// drag a real total toward a number the UI would then present as all-time
    /// truth. Returns `nil` when no provider contributed at all, so the surface
    /// renders "—" rather than a confident "0 tokens all-time".
    public static func lifetimeTotal(
        in snapshots: [ProviderSnapshot],
        hiddenProviders: Set<ProviderID> = []
    ) -> LifetimeTotal? {
        var tokens = 0
        var confidences: [MetricConfidence] = []
        var usedFallback = false
        var contributors = 0

        for snapshot in snapshots where !hiddenProviders.contains(snapshot.providerID) {
            if let reported = snapshot.lifetimeUsage?.totalTokens {
                tokens += reported
                confidences.append(snapshot.lifetimeUsage?.confidence ?? .unavailable)
                contributors += 1
            } else if let daily = snapshot.dailyTotals, !daily.isEmpty {
                tokens += daily.values.reduce(0, +)
                // Locally summed day buckets — exactly what `.localParsed` means.
                confidences.append(.localParsed)
                usedFallback = true
                contributors += 1
            }
        }

        guard contributors > 0 else { return nil }

        return LifetimeTotal(
            tokens: tokens,
            confidence: worstConfidence(confidences),
            usedDailyFallback: usedFallback,
            contributingProviders: contributors
        )
    }

    /// Degradation order shared with `TokenUsage.merging` — a merged metric is only
    /// as good as its weakest input.
    public static func worstConfidence(_ confidences: [MetricConfidence]) -> MetricConfidence {
        let order: [MetricConfidence] = [.exact, .providerReported, .localParsed, .estimated, .unavailable]
        let ranks = confidences.compactMap { order.firstIndex(of: $0) }
        guard let worst = ranks.max() else { return .unavailable }
        return order[worst]
    }

    // MARK: - Today across providers

    /// Today's per-metric usage merged across the given snapshots, via the Core
    /// merge (so confidence degrades to the weakest contributor exactly as it does
    /// everywhere else). Callers pass an already-filtered list — this makes no
    /// judgement about which providers count.
    ///
    /// Shared by the Overview hero and the `01 / OVERVIEW` tab pill so the two can
    /// never print different totals for the same day.
    ///
    /// Only providers that actually measured something contribute. Two reasons,
    /// both about the confidence the badge prints:
    /// - Seeding the fold with `.unavailable` would pin every result to
    ///   `.unavailable`, since `merging` keeps the weaker of two confidences.
    /// - So would including a provider that reports no token usage at all — a
    ///   Cursor with nothing to say would make a day of `.exact` Claude tokens
    ///   render as "UNAVAILABLE".
    ///
    /// Totals are unaffected: an unmeasured provider merges as zeros anyway. Same
    /// principle as `lifetimeTotal` — absent is not zero, and it is not evidence
    /// against the providers that did report.
    public static func mergedTodayUsage(in snapshots: [ProviderSnapshot]) -> TokenUsage {
        var iterator = snapshots.lazy
            .map(\.todayUsage)
            .filter { $0.totalTokens != nil }
            .makeIterator()
        guard var merged = iterator.next() else { return .unavailable }
        while let next = iterator.next() { merged = merged.merging(next) }
        return merged
    }

    // MARK: - Provider chip stat (WP-4 chip strip)

    /// The ONE live number a provider chip shows. The chip strip replaced the
    /// sidebar's provider rows, and a chip has room for exactly one figure, so
    /// this picks the most informative one the provider actually has.
    ///
    /// Deliberately *not* the same metric the Overview `Limits` rows show: those
    /// carry quota pressure (bar, pace notch, countdown), so a chip leads with
    /// volume and only falls back to utilization when there is no token signal.
    /// Two surfaces at two altitudes instead of the same list printed twice.
    public enum ChipStat: Sendable, Equatable {
        /// Today's total tokens. `0` is a real reading, not a placeholder.
        case tokens(Int)
        /// Tightest live window, 0…100 — used when the provider reports no tokens.
        case utilization(Double)
        /// Plan label (e.g. "Pro") for a plan-only provider with neither number.
        case plan(String)
        /// No snapshot yet and a sync is in flight — the chip's loading state.
        case syncing
        /// Detected, but nothing honest to show yet.
        case none
    }

    /// Resolve a provider's chip stat.
    ///
    /// Precedence: syncing → today's tokens (when the provider reports any) →
    /// tightest live window → plan label → nothing. `planLabel` is passed in
    /// rather than parsed here so this file keeps its Foundation + Core-only
    /// dependency contract.
    public static func chipStat(
        providerID: ProviderID,
        snapshot: ProviderSnapshot?,
        utilizations: [Utilization],
        planLabel: String?,
        isLoading: Bool
    ) -> ChipStat {
        guard let snapshot else { return isLoading ? .syncing : .none }

        let todayTokens = snapshot.todayUsage.totalTokens
        if let todayTokens, todayTokens > 0 { return .tokens(todayTokens) }

        let tightest = tightestWindow(in: utilizations.filter { $0.providerID == providerID })
        if let tightest { return .utilization(tightest.usedPercent) }

        // A genuine zero only outranks the plan label — it never outranks a live
        // window, since "0 today" next to a 94%-full week is the less useful read.
        if todayTokens != nil { return .tokens(0) }

        if let planLabel, !planLabel.isEmpty { return .plan(planLabel) }
        return .none
    }

    // MARK: - Value-surface formatting (#23)

    /// Placeholder for every unknown number on the value surface. An unset plan
    /// cost or an unpriceable provider must never render as "$0.00" or "0×".
    public static let unknownPlaceholder = "—"

    /// USD in the fixed two-decimal form the value table uses (`$684.20`).
    /// Locale-independent on purpose: these are USD figures from the pricing
    /// tables, not amounts in the user's local currency, and a locale-shifted
    /// separator would also make the table's mono columns stop lining up.
    public static func formatUSD(_ value: Double?) -> String {
        guard let value, value.isFinite else { return unknownPlaceholder }
        return usdFormatter.string(from: NSNumber(value: value)).map { "$\($0)" } ?? unknownPlaceholder
    }

    /// Value multiple as `3.4×` (true multiplication sign, not the letter x).
    /// `nil`/non-finite renders the placeholder — a multiple over an unset or
    /// zero plan cost is undefined, never "0×" or "∞".
    public static func formatMultiple(_ value: Double?) -> String {
        guard let value, value.isFinite else { return unknownPlaceholder }
        return "\(multipleFormatter.string(from: NSNumber(value: value)) ?? "\(value)")\u{00D7}"
    }

    private static let usdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let multipleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}
