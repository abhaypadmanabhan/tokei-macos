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
    /// Which entry of `accounts` the headline `quotaWindows` were taken from, when the
    /// provider picked one rather than aggregating.
    ///
    /// The provider calls the shared `AccountQuotaDecision`; surfaces read this legacy row
    /// id instead of re-deriving the rule. The public agent schema separately projects the
    /// stable `accountID`. `nil` when there is no account breakdown or usable reading.
    public let headlineAccountID: String?

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
        accounts: [ProviderAccountUsage]? = nil,
        headlineAccountID: String? = nil
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
        self.headlineAccountID = headlineAccountID
    }
}

public enum AccountQuotaStatus: String, Sendable {
    case eligible
    case expiredCredentials
    case cooldown
    case disabled
    case requestFailed
    case noQuotaSource
    case unknown
}

/// One account's own usage within a provider that supports several signed-in accounts.
///
/// Kept as a field on a single `ProviderSnapshot` rather than emitting one snapshot per
/// account, because `ProviderSnapshot.id` *is* its `ProviderID` — duplicate ids would
/// break `Identifiable` for every store and view that keys off it. The aggregate stays
/// the headline; this is the breakdown behind it.
public struct ProviderAccountUsage: Sendable, Identifiable {
    /// Legacy local profile id, currently the canonical config-directory path.
    public let id: String
    /// Stable provider-scoped identity. `id` remains the legacy local path for compatibility.
    public let accountID: String?
    /// Verified literal environment selector for this account, when the adapter has one.
    public let selector: AccountSelector?
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
    /// Structured quota availability for this account. This is deliberately separate from
    /// `quotaWindows`: an empty window set cannot distinguish expired auth from disabled
    /// network usage or a provider response with no quota source.
    public let quotaStatus: AccountQuotaStatus
    /// Short, provider-authored diagnostic only. Never stores raw responses or credentials.
    public let quotaStatusDetail: String?

    public init(
        id: String,
        accountID: String? = nil,
        selector: AccountSelector? = nil,
        label: String,
        quotaWindows: [QuotaWindow],
        todayUsage: TokenUsage,
        dailyTotals: [Date: Int]? = nil,
        configDirectories: [String] = [],
        unreadableDirectories: [String] = [],
        quotaStatus: AccountQuotaStatus = .unknown,
        quotaStatusDetail: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.selector = selector
        self.label = label
        self.quotaWindows = quotaWindows
        self.todayUsage = todayUsage
        self.dailyTotals = dailyTotals
        self.configDirectories = configDirectories
        self.unreadableDirectories = unreadableDirectories
        self.quotaStatus = quotaStatus
        self.quotaStatusDetail = quotaStatusDetail
    }
}
