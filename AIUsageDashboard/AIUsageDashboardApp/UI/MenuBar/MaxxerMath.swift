import Foundation
import AIUsageDashboardCore

/// Pure math for the Token-Maxxer surface — pace against a linear burn, the
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

    // MARK: - Linear-pace verdict

    /// How actual consumption compares to a perfectly linear burn of the window.
    /// Positive-framed on purpose (token-maxxer voice: room to use, not scolding):
    /// - `.ahead`    — spent more than the elapsed fraction; burning fast.
    /// - `.onPace`   — within the tolerance band of linear pace.
    /// - `.headroom` — spent less than elapsed; budget to spare.
    public enum PaceVerdict: String, Sendable, Equatable {
        case ahead
        case onPace
        case headroom
    }

    /// The result of a pace computation for one quota window.
    public struct QuotaPace: Sendable, Equatable {
        /// Fraction of the window elapsed, 0…1 — where the expected-pace notch sits.
        public let elapsedFraction: Double
        /// Expected utilization at linear pace, 0…100 (`elapsedFraction * 100`).
        public let expectedPercent: Double
        /// `usedPercent - expectedPercent`, positive = ahead of linear.
        public let delta: Double
        public let verdict: PaceVerdict

        public init(elapsedFraction: Double, expectedPercent: Double, delta: Double, verdict: PaceVerdict) {
            self.elapsedFraction = elapsedFraction
            self.expectedPercent = expectedPercent
            self.delta = delta
            self.verdict = verdict
        }
    }

    /// The canonical span of a rolling quota window, used to place the elapsed-pace
    /// notch. `nil` for window types with no fixed linear span (a session, a credit
    /// balance, a per-model or lifetime total) — those degrade to "no pace" rather
    /// than inventing a denominator.
    ///
    /// Monthly is treated as 30 days: `resetAt` gives the window's END, and without
    /// the exact anchor a 30-day span is the honest linear approximation for a notch.
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

    /// Compute pace for a window against a linear burn.
    ///
    /// Returns `nil` (→ the UI shows "—", never crashes) when the window has no
    /// canonical span or no `resetAt` — i.e. when an expected-pace position is
    /// undefined. `elapsedFraction` is clamped to 0…1 so a reset just in the past
    /// or a clock skew can't push the notch off the bar.
    ///
    /// - Parameters:
    ///   - usedPercent: actual utilization 0…100 (already `used / limit`).
    ///   - windowType: the quota window type (drives the canonical span).
    ///   - resetAt: when the window refills; its span is `[resetAt - duration, resetAt]`.
    ///   - now: current instant (injected — no wall clock here).
    ///   - tolerance: half-width of the on-pace band in percentage points (default 5).
    public static func pace(
        usedPercent: Double,
        windowType: QuotaWindowType,
        resetAt: Date?,
        now: Date,
        tolerance: Double = 5
    ) -> QuotaPace? {
        guard let duration = canonicalWindowDuration(for: windowType), duration > 0,
              let resetAt else { return nil }

        let remaining = resetAt.timeIntervalSince(now)
        let elapsed = duration - remaining
        let elapsedFraction = min(1, max(0, elapsed / duration))
        let expectedPercent = elapsedFraction * 100
        let delta = usedPercent - expectedPercent

        let verdict: PaceVerdict
        if delta > tolerance {
            verdict = .ahead
        } else if delta < -tolerance {
            verdict = .headroom
        } else {
            verdict = .onPace
        }

        return QuotaPace(
            elapsedFraction: elapsedFraction,
            expectedPercent: expectedPercent,
            delta: delta,
            verdict: verdict
        )
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

    /// The provider worth routing new work to: the least-filled window, but only
    /// when the suggestion is actually useful. `nil` (no chip) unless
    /// - there are at least two live readings (routing implies a choice), AND
    /// - the least-filled has genuine headroom (`usedPercent <= maxUsedPercent`), AND
    /// - it is meaningfully emptier than the tightest (`spread >= minSpread`),
    ///   so we never nudge toward something that's also nearly full.
    ///
    /// Deterministic: on a tie for least-filled the first-seen reading wins.
    public static func routeTarget(
        in utilizations: [Utilization],
        maxUsedPercent: Double = 70,
        minSpread: Double = 15
    ) -> Utilization? {
        guard utilizations.count >= 2 else { return nil }

        let least = utilizations.reduce(nil) { (current: Utilization?, candidate) in
            guard let current else { return candidate }
            return candidate.usedPercent < current.usedPercent ? candidate : current
        }
        guard let least, let tightest = tightestWindow(in: utilizations) else { return nil }
        guard least.usedPercent <= maxUsedPercent,
              tightest.usedPercent - least.usedPercent >= minSpread else { return nil }
        return least
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
