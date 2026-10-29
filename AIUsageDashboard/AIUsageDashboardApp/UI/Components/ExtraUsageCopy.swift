import Foundation
import AIUsageDashboardCore

/// Words for Claude's extra usage (overage dollars on top of the plan), read from the
/// `.credits` window with bucket `claude_extra_usage` (§4 contract 3):
/// "Extra usage $21.52 of $50.00 · off, out of credits". A balance, never a quota ceiling:
/// it gets no pace, no forecast and never counts as the tightest reading.
enum ExtraUsageCopy {
    static let bucketKey = "claude_extra_usage"

    static func isExtraUsage(_ window: QuotaWindow) -> Bool {
        window.type == .credits && window.bucketKey == bucketKey
    }

    /// The extra-usage window in a snapshot (its own windows or any account's), if any.
    static func window(in snapshot: ProviderSnapshot?) -> QuotaWindow? {
        guard let snapshot else { return nil }
        let windows = snapshot.quotaWindows + (snapshot.accounts ?? []).flatMap(\.quotaWindows)
        return windows.first(where: isExtraUsage)
    }

    /// "$21.52 of $50.00", "$21.52 used" without a limit; `nil` with no amount at all.
    static func amounts(_ window: QuotaWindow) -> String? {
        let used = window.used ?? window.limit.flatMap { limit in window.remaining.map { limit - $0 } }
        guard let used else { return nil }
        guard let limit = window.limit, limit > 0 else { return "\(MaxxerMath.formatUSD(used)) used" }
        return "\(MaxxerMath.formatUSD(used)) of \(MaxxerMath.formatUSD(limit))"
    }

    /// Whether it is switched on and why not, from the provider's own words in `source`
    /// (Anthropic reports `is_enabled` and `disabled_reason`, e.g. `out_of_credits`).
    /// `nil` when the source says neither.
    static func status(_ window: QuotaWindow) -> String? {
        let source = window.source.lowercased()
        var parts: [String] = []
        let compact = source.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\"", with: "")
        if source.contains("disabled") || compact.contains("enabled=false") || compact.contains("enabled:false") {
            parts.append("off")
        }
        if source.contains("out_of_credits") || source.contains("out of credits") {
            parts.append("out of credits")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "Extra usage $21.52 of $50.00 · off, out of credits".
    static func line(_ window: QuotaWindow) -> String? {
        guard let amounts = amounts(window) else { return nil }
        let label = window.label ?? "Extra usage"
        guard let status = status(window) else { return "\(label) \(amounts)" }
        return "\(label) \(amounts) · \(status)"
    }

    /// Share of the limit spent, 0…1, for the thin bar; `nil` without a limit.
    static func fraction(_ window: QuotaWindow) -> Double? {
        guard let limit = window.limit, limit > 0, let used = window.used else { return nil }
        return min(1, max(0, used / limit))
    }
}
