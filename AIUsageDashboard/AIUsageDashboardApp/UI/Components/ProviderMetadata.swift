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

/// Static, UI-only facts about each provider that never need Core access: local
/// paths, live-quota settings, and plan/tier display text.
enum ProviderMetadata {
    static let liveQuotaProviders: Set<ProviderID> = [.claudeCode, .codex, .cursor, .antigravity, .gemini]

    /// Network toggles that are on until the user turns them off (registered at launch, so
    /// `UserDefaults.bool(forKey:)` and `@AppStorage` read `true` when the key is unset).
    static let networkDefaultsOn: [String: Bool] = ["geminiNetworkUsageEnabled": true]

    static func showsPendingQuota(for providerID: ProviderID) -> Bool {
        // Codex still reads local logs when its optional CLI probe has no window.
        providerID != .codex && liveQuotaProviders.contains(providerID)
    }

    static func liveQuotaEnabledKey(for providerID: ProviderID) -> String? {
        switch providerID {
        case .claudeCode: return "claudeNetworkUsageEnabled"
        case .codex: return CodexProvider.liveQuotaEnabledKey
        case .cursor: return "cursorNetworkUsageEnabled"
        case .antigravity: return "antigravityOnlineQuotaEnabled"
        case .gemini: return "geminiNetworkUsageEnabled"
        default: return nil
        }
    }

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
        case .gemini:
            return ["~/.gemini/oauth_creds.json"]
        case .copilot:
            return [
                "~/.copilot",
                "~/.vscode/extensions",
                "~/Library/Application Support/Code/User/globalStorage/github.copilot-chat"
            ]
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

/// What a provider's Overview › Quota row says when it has no live reading. Each case is
/// a state a person can act on or ignore; none is a spinner that never ends.
enum QuotaGap: Equatable {
    /// Its live-quota toggle is off: say so, with one action into Settings.
    case networkOff
    /// Toggle on and a sync is running right now.
    case checking
    /// Toggle on, the last sync finished, nothing usable came back; the reason when known.
    case noReading(reason: String?)
    /// No live connector at all: named once on the "no live quota" line, never a bar.
    case noSource

    /// Why a provider with no live reading has none.
    static func classify(
        _ providerID: ProviderID,
        isEnabled: (String) -> Bool,
        isSyncing: Bool,
        reason: String?
    ) -> QuotaGap {
        guard let key = ProviderMetadata.liveQuotaEnabledKey(for: providerID) else { return .noSource }
        if !isEnabled(key) { return .networkOff }
        // Codex reads local logs when its optional quota probe has nothing; that is not a
        // pending reading, so it joins the no-source line.
        guard ProviderMetadata.showsPendingQuota(for: providerID) else { return .noSource }
        return isSyncing ? .checking : .noReading(reason: reason)
    }

    /// The provider's own account status, in words, when it says why there is no reading.
    static func reason(for snapshot: ProviderSnapshot?) -> String? {
        let statuses = (snapshot?.accounts ?? []).map(\.quotaStatus)
        if statuses.contains(.expiredCredentials) { return "sign-in expired" }
        if statuses.contains(.cooldown) { return "rate-limited, will retry" }
        if statuses.contains(.requestFailed) { return "the request failed" }
        if statuses.contains(.noQuotaSource) { return "the provider returned no quota" }
        return nil
    }
}
