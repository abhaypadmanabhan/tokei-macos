import Foundation

/// A known provider subscription tier and its published monthly USD price.
/// Offered by the Settings preset picker to prefill `MaxxerPlanCostStore` —
/// selecting one is a manual entry like any other; the user can still edit it
/// afterward (#51).
public struct PlanPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let monthlyUSD: Double

    public init(id: String, label: String, monthlyUSD: Double) {
        self.id = id
        self.label = label
        self.monthlyUSD = monthlyUSD
    }
}

/// The known-plan catalog offered by the Settings preset picker, keyed by
/// `ProviderID.rawValue`. Prices are each provider's published list price for
/// that tier as of 2026-07; time-varying promos (first-month discounts,
/// student pricing) are explicitly out of scope for presets — the user keeps
/// the field current for those (#51). A provider with no catalog entry
/// returns `[]` so its row renders no picker, never a dead one.
public enum PlanPresetCatalog {
    public static func presets(for providerID: String) -> [PlanPreset] {
        switch providerID {
        case "claude_code":
            // TODO(#51): Tokei models a single claude_code provider, so a
            // multi-account setup (e.g. 2× Max) has no combined preset here —
            // open modeling question, not addressed by this catalog.
            return [
                PlanPreset(id: "claude_pro", label: "Pro", monthlyUSD: 20),
                PlanPreset(id: "claude_max", label: "Max", monthlyUSD: 100)
            ]
        case "codex":
            return [PlanPreset(id: "codex_plus", label: "Plus", monthlyUSD: 20)]
        case "cursor":
            return [PlanPreset(id: "cursor_pro", label: "Pro", monthlyUSD: 20)]
        case "cline":
            return [PlanPreset(id: "cline_pro", label: "Pro", monthlyUSD: 10)]
        case "antigravity":
            return [PlanPreset(id: "antigravity_pro", label: "Pro", monthlyUSD: 5)]
        default:
            return []
        }
    }
}

/// A best-effort plan tier detected from a provider's own local/API signal.
/// Always paired with a `source` description so the UI can disclose where the
/// suggestion came from — detection is never silently trusted (#51).
public struct DetectedPlan: Equatable, Sendable {
    public let presetID: String
    public let monthlyUSD: Double
    public let source: String

    public init(presetID: String, monthlyUSD: Double, source: String) {
        self.presetID = presetID
        self.monthlyUSD = monthlyUSD
        self.source = source
    }
}

/// Best-effort plan-tier detection, one function per provider so each signal
/// stays independently swappable/testable. Every path returns `nil` — never
/// `$0` — when the signal is missing or unrecognized (#51).
public enum PlanDetector {
    /// Cursor's composed plan label (`QuotaWindow.label`, e.g. `"Pro (active)"`
    /// or the raw `usage-summary` `membershipType` alone, e.g. `"pro"`) — strip
    /// any trailing `"(status)"` and match the tier name against the Cursor
    /// preset catalog by display label, case-insensitively. Unrecognized or
    /// unpriced tiers (e.g. "Free", "Business") return `nil`.
    public static func detectCursorPlan(planLabel: String?) -> DetectedPlan? {
        guard let planLabel else { return nil }
        let tierName = planLabel
            .split(separator: "(", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !tierName.isEmpty else { return nil }

        guard let preset = PlanPresetCatalog.presets(for: "cursor")
            .first(where: { $0.label.caseInsensitiveCompare(tierName) == .orderedSame })
        else { return nil }

        return DetectedPlan(presetID: preset.id, monthlyUSD: preset.monthlyUSD, source: "Cursor's reported plan")
    }

    // Research stubs (#51) — no cheap local/API signal wired up yet:
    //   - Claude: OAuth usage endpoint may expose plan tier (Max/Pro).
    //   - Gemini/Antigravity: loadCodeAssist tier fields.
    //   - Cline: providers.json / app.cline.bot (undocumented).
    //   - Codex: auth.json account plan.
    // Each returns nil until a signal is implemented — never fabricate $0.
    public static func detectClaudePlan() -> DetectedPlan? { nil }
    public static func detectGeminiPlan() -> DetectedPlan? { nil }
    public static func detectAntigravityPlan() -> DetectedPlan? { nil }
    public static func detectClinePlan() -> DetectedPlan? { nil }
    public static func detectCodexPlan() -> DetectedPlan? { nil }

    /// What the Settings row should offer to prefill: `nil` once the user has
    /// a saved plan cost for this provider — their value always stands, so a
    /// detected signal can never overwrite it — or when there's no detection.
    public static func suggestedPlan(existingValue: Double?, detected: DetectedPlan?) -> DetectedPlan? {
        existingValue == nil ? detected : nil
    }
}
