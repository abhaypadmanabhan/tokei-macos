import Foundation
import AIUsageDashboardCore

/// Honest capability tier for a provider row, derived entirely from the public
/// `ProviderSnapshot` shape (no access to the provider-side `ProviderCapabilities`
/// OptionSet, which never crosses into UI). A provider can move between tiers as
/// its snapshot changes (e.g. Cursor moves from `.planOnly` to `.fullMetrics` the
/// moment the network-usage toggle starts returning real token data) — the UI
/// never hardcodes a tier per provider ID.
enum ProviderCapabilityTier {
    case fullMetrics
    case planOnly
    case detectionOnly
    case notInstalled

    var label: String {
        switch self {
        case .fullMetrics: return "FULL METRICS"
        case .planOnly: return "PLAN ONLY / ENABLE ONLINE"
        case .detectionOnly: return "DETECTION ONLY"
        case .notInstalled: return "NOT INSTALLED"
        }
    }

    static func classify(_ snapshot: ProviderSnapshot?) -> ProviderCapabilityTier {
        guard let snapshot else { return .notInstalled }

        let hasTokenData = snapshot.todayUsage.confidence != .unavailable
            || snapshot.weekUsage.confidence != .unavailable
            || (snapshot.monthUsage?.confidence).map { $0 != .unavailable } ?? false
            || (snapshot.lifetimeUsage?.confidence).map { $0 != .unavailable } ?? false
        if hasTokenData { return .fullMetrics }

        let hasPlanSignal = ProviderMetadata.planText(from: snapshot.warnings) != nil
        let hasQuotaSignal = snapshot.quotaWindows.contains { $0.confidence != .unavailable }
        let hasCostSignal = snapshot.costUsage?.amount != nil
        if hasPlanSignal || hasQuotaSignal || hasCostSignal { return .planOnly }

        return .detectionOnly
    }
}

/// Static, UI-only facts about each provider that never need Core access: the
/// exact local path(s) Tokei reads, and how to pull the plan/tier string out of
/// the one sanctioned channel for that data (`ProviderWarning`, frozen contract
/// per the Patch Bible — plan/tier/credits never get a new stored field).
enum ProviderMetadata {
    /// Exact local path(s) this provider reads from, for the "we only read this"
    /// disclosure. Sourced from each provider's real default file location
    /// (verified against Core/Providers/*.swift and the Patch Bible's machine-
    /// verified paths for Cursor/Antigravity) — never a guess.
    static func localPaths(for providerID: ProviderID) -> [String] {
        switch providerID {
        case .claudeCode:
            return ["~/.claude/projects"]
        case .codex:
            return ["~/.codex/sessions"]
        case .cline:
            return ["~/.cline/data/sessions"]
        case .cursor:
            return ["~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"]
        case .antigravity:
            return ["~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb"]
        case .opencode:
            return ["~/.local/share/opencode"]
        }
    }

    /// Extracts plan/tier text from a `"Plan: <text>"` info warning. This is a
    /// convention, not a type — the Cursor/Antigravity connectors (Round 2 WP-1/2)
    /// are documented in the Bible to surface plan/tier exactly this way since
    /// `ProviderSnapshot` gets no new stored field this round. Integration-verify
    /// the literal wording once those packages merge.
    static func planText(from warnings: [ProviderWarning]) -> String? {
        for warning in warnings where warning.level == .info {
            if let range = warning.message.range(of: "Plan:", options: [.caseInsensitive]) {
                let text = warning.message[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
}
