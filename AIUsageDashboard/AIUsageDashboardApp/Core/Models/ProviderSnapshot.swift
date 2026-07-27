import Foundation

public struct ProviderSnapshot: Sendable, Identifiable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let displayName: String
    public let authStatus: AuthStatus
    public let quotaWindows: [QuotaWindow]
    public let todayUsage: TokenUsage
    public let weekUsage: TokenUsage
    public let monthUsage: TokenUsage?
    public let lifetimeUsage: TokenUsage?
    public let costUsage: CostUsage?
    public let warnings: [ProviderWarning]
    public let lastSyncedAt: Date?
    /// Total tokens per calendar day (start-of-day key), when the provider can derive them.
    public let dailyTotals: [Date: Int]?
    /// Total tokens per calendar hour (hour-truncated key), when timestamped records are available.
    public let hourlyTotals: [Date: Int]?
    /// Per-account breakdown for providers that support several signed-in accounts.
    /// `nil` for single-account providers. The top-level fields stay the aggregate.
    public let accounts: [ProviderAccountUsage]?

    public init(
        providerID: ProviderID,
        displayName: String,
        authStatus: AuthStatus,
        quotaWindows: [QuotaWindow] = [],
        todayUsage: TokenUsage,
        weekUsage: TokenUsage,
        monthUsage: TokenUsage? = nil,
        lifetimeUsage: TokenUsage? = nil,
        costUsage: CostUsage? = nil,
        warnings: [ProviderWarning] = [],
        lastSyncedAt: Date? = nil,
        dailyTotals: [Date: Int]? = nil,
        hourlyTotals: [Date: Int]? = nil,
        accounts: [ProviderAccountUsage]? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.authStatus = authStatus
        self.quotaWindows = quotaWindows
        self.todayUsage = todayUsage
        self.weekUsage = weekUsage
        self.monthUsage = monthUsage
        self.lifetimeUsage = lifetimeUsage
        self.costUsage = costUsage
        self.warnings = warnings
        self.lastSyncedAt = lastSyncedAt
        self.dailyTotals = dailyTotals
        self.hourlyTotals = hourlyTotals
        self.accounts = accounts
    }
}

/// One account's own usage within a provider that supports several signed-in accounts
/// (currently only Claude Code, via `CLAUDE_CONFIG_DIR`).
///
/// Kept as a field on a single `ProviderSnapshot` rather than emitting one snapshot per
/// account, because `ProviderSnapshot.id` *is* its `ProviderID` — duplicate ids would
/// break `Identifiable` for every store and view that keys off it. The aggregate stays
/// the headline; this is the breakdown behind it.
public struct ProviderAccountUsage: Sendable, Identifiable {
    /// Stable id — the account's config-directory path.
    public let id: String
    /// Short label, e.g. `"default"` or `"account-2"`.
    public let label: String
    public let quotaWindows: [QuotaWindow]
    public let todayUsage: TokenUsage

    public init(id: String, label: String, quotaWindows: [QuotaWindow], todayUsage: TokenUsage) {
        self.id = id
        self.label = label
        self.quotaWindows = quotaWindows
        self.todayUsage = todayUsage
    }
}
