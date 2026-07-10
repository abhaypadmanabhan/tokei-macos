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
        hourlyTotals: [Date: Int]? = nil
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
    }
}
