import Foundation

/// Pure mapping from the snapshots Tokei already collects to the unified
/// `Utilization` contract — no I/O, no network, no clock. Given the same
/// snapshots it always returns the same values, which is what makes it trivially
/// testable and safe to call from any surface (view model, menu bar, future widget).
public enum UtilizationEngine {
    /// Map every provider's `quotaWindows` to `Utilization` values, omitting
    /// (never zero-filling) windows and providers with no computable quota.
    ///
    /// A window is computable when it has a positive `limit` and either a `used`
    /// or a `remaining` reading; anything else is dropped rather than invented.
    public static func utilizations(from snapshots: [ProviderSnapshot]) -> [Utilization] {
        snapshots.flatMap { snapshot -> [Utilization] in
            let plan = planLabel(from: snapshot.warnings)
            return snapshot.quotaWindows.compactMap { window in
                utilization(from: window, plan: plan)
            }
        }
    }

    /// The single "today's utilization across all plans" value, or `nil` when no
    /// provider reported usable quota.
    ///
    /// For each covered provider we take its **peak** window utilization (the
    /// tightest ceiling), then average those peaks across providers. Coverage is
    /// `.partial` when a provider exposed quota windows but none were computable —
    /// it is omitted from the mean, never zero-filled.
    public static func aggregate(from snapshots: [ProviderSnapshot]) -> AggregateUtilization? {
        // Peak utilization per provider (the reading that drives the number).
        let peakByProvider = Dictionary(grouping: utilizations(from: snapshots), by: \.providerID)
            .compactMapValues { $0.max(by: { $0.usedPercent < $1.usedPercent }) }

        guard !peakByProvider.isEmpty else { return nil }

        // A provider that exposed windows but produced no computable utilization is
        // "missing" (partial coverage) — distinct from a provider that has no quota
        // concept at all, which simply isn't counted.
        let hasMissingQuotaProvider = snapshots.contains { snapshot in
            !snapshot.quotaWindows.isEmpty && peakByProvider[snapshot.providerID] == nil
        }

        let peaks = Array(peakByProvider.values)
        let mean = peaks.reduce(0) { $0 + $1.usedPercent } / Double(peaks.count)
        let coveredProviders = ProviderID.allCases.filter { peakByProvider[$0] != nil }
        let confidence = peaks.min(by: { rank($0.confidence) < rank($1.confidence) })?.confidence ?? .unavailable

        return AggregateUtilization(
            usedPercent: mean,
            coveredProviders: coveredProviders,
            coverage: hasMissingQuotaProvider ? .partial : .complete,
            confidence: confidence
        )
    }

    // MARK: - Per-window mapping

    private static func utilization(from window: QuotaWindow, plan: String?) -> Utilization? {
        guard let percent = usedPercent(from: window) else { return nil }
        return Utilization(
            providerID: window.providerID,
            window: window.type,
            usedPercent: percent,
            resetAt: window.resetAt,
            plan: plan,
            confidence: window.confidence,
            coverage: .complete
        )
    }

    /// A window carries `used`/`limit` as a percentage gauge (Tokei's convention:
    /// `limit == 100`), but this stays correct for any real limit — it divides.
    /// Falls back to `limit - remaining` when only `remaining` is reported. Returns
    /// `nil` (omit) when there is no denominator or no numerator.
    private static func usedPercent(from window: QuotaWindow) -> Double? {
        guard let limit = window.limit, limit > 0 else { return nil }
        guard let used = window.used ?? window.remaining.map({ limit - $0 }) else { return nil }
        return min(100, max(0, used / limit * 100))
    }

    // MARK: - Plan extraction

    /// Providers surface their plan as an `.info` warning like `"Plan: Pro · yearly"`
    /// (the sanctioned plan/tier channel — see `CursorProvider` / `AntigravityProvider`).
    /// Pull the label out of the first such warning; return `nil` when none is present.
    private static func planLabel(from warnings: [ProviderWarning]) -> String? {
        for warning in warnings where warning.level == .info {
            guard let range = warning.message.range(of: "Plan:", options: [.caseInsensitive]) else {
                continue
            }
            let label = warning.message[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !label.isEmpty { return label }
        }
        return nil
    }

    // MARK: - Confidence ordering

    /// Lower rank = more conservative. The aggregate reports the least-trustworthy
    /// confidence among the readings behind it, so it never over-promises.
    private static func rank(_ confidence: MetricConfidence) -> Int {
        switch confidence {
        case .unavailable: return 0
        case .estimated: return 1
        case .localParsed: return 2
        case .providerReported: return 3
        case .exact: return 4
        }
    }
}
