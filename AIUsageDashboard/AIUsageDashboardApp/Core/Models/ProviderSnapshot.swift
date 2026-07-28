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
    /// This account's own tokens per calendar day (start-of-day key) — the series the
    /// provider merges into `ProviderSnapshot.dailyTotals`, kept unmerged so a surface can
    /// draw one line per account. `nil` when the provider derives no per-account series.
    public let dailyTotals: [Date: Int]?
    /// Every config directory this account owns, as absolute paths. One Anthropic identity
    /// can be signed in from several `CLAUDE_CONFIG_DIR`s, and this row's numbers are the
    /// union of all of them — without this the UI cannot say *why* three directories show
    /// up as two accounts.
    public let configDirectories: [String]
    /// Directories that exist but could not be read on this refresh. Their usage is missing
    /// from `todayUsage` and `dailyTotals`, so a surface can mark the row incomplete instead
    /// of presenting a confident number with a hole in it. Empty is the normal case.
    public let unreadableDirectories: [String]

    public init(
        id: String,
        label: String,
        quotaWindows: [QuotaWindow],
        todayUsage: TokenUsage,
        dailyTotals: [Date: Int]? = nil,
        configDirectories: [String] = [],
        unreadableDirectories: [String] = []
    ) {
        self.id = id
        self.label = label
        self.quotaWindows = quotaWindows
        self.todayUsage = todayUsage
        self.dailyTotals = dailyTotals
        self.configDirectories = configDirectories
        self.unreadableDirectories = unreadableDirectories
    }
}
