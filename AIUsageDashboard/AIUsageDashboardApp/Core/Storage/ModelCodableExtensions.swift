import Foundation

// MARK: - Raw-representable enums

extension ProviderID: Codable {}
extension AuthStatus: Codable {}
extension MetricConfidence: Codable {}
extension QuotaWindowType: Codable {}
extension ProviderWarning.Level: Codable {}

// MARK: - Value types with custom Codable implementations
//
// Synthesized Codable conformance is only available in the same file as the
// declaration, so these conformances are implemented manually.

extension ProviderSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case providerID
        case displayName
        case authStatus
        case quotaWindows
        case todayUsage
        case weekUsage
        case monthUsage
        case lifetimeUsage
        case costUsage
        case warnings
        case lastSyncedAt
        case dailyTotals
        case hourlyTotals
        case accounts
        case headlineAccountID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(ProviderID.self, forKey: .providerID)
        displayName = try container.decode(String.self, forKey: .displayName)
        authStatus = try container.decode(AuthStatus.self, forKey: .authStatus)
        quotaWindows = try container.decode([QuotaWindow].self, forKey: .quotaWindows)
        todayUsage = try container.decode(TokenUsage.self, forKey: .todayUsage)
        weekUsage = try container.decode(TokenUsage.self, forKey: .weekUsage)
        monthUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .monthUsage)
        lifetimeUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .lifetimeUsage)
        costUsage = try container.decodeIfPresent(CostUsage.self, forKey: .costUsage)
        warnings = try container.decode([ProviderWarning].self, forKey: .warnings)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        dailyTotals = try container.decodeIfPresent([Date: Int].self, forKey: .dailyTotals)
        hourlyTotals = try container.decodeIfPresent([Date: Int].self, forKey: .hourlyTotals)
        // Absent in snapshots written before multi-account support — decodes as nil.
        accounts = try container.decodeIfPresent([ProviderAccountUsage].self, forKey: .accounts)
        headlineAccountID = try container.decodeIfPresent(String.self, forKey: .headlineAccountID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(authStatus, forKey: .authStatus)
        try container.encode(quotaWindows, forKey: .quotaWindows)
        try container.encode(todayUsage, forKey: .todayUsage)
        try container.encode(weekUsage, forKey: .weekUsage)
        try container.encodeIfPresent(monthUsage, forKey: .monthUsage)
        try container.encodeIfPresent(lifetimeUsage, forKey: .lifetimeUsage)
        try container.encodeIfPresent(costUsage, forKey: .costUsage)
        try container.encode(warnings, forKey: .warnings)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encodeIfPresent(dailyTotals, forKey: .dailyTotals)
        try container.encodeIfPresent(hourlyTotals, forKey: .hourlyTotals)
        try container.encodeIfPresent(accounts, forKey: .accounts)
        try container.encodeIfPresent(headlineAccountID, forKey: .headlineAccountID)
    }
}

extension ProviderAccountUsage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case quotaWindows
        case todayUsage
        case dailyTotals
        case configDirectories
        case unreadableDirectories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        quotaWindows = try container.decode([QuotaWindow].self, forKey: .quotaWindows)
        todayUsage = try container.decode(TokenUsage.self, forKey: .todayUsage)
        // The three below arrived with per-account history; snapshots written before it
        // simply lack the keys, so they decode as "no series, no directories known"
        // rather than failing the whole cache.
        dailyTotals = try container.decodeIfPresent([Date: Int].self, forKey: .dailyTotals)
        configDirectories = try container.decodeIfPresent([String].self, forKey: .configDirectories) ?? []
        unreadableDirectories = try container.decodeIfPresent([String].self, forKey: .unreadableDirectories) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(quotaWindows, forKey: .quotaWindows)
        try container.encode(todayUsage, forKey: .todayUsage)
        try container.encodeIfPresent(dailyTotals, forKey: .dailyTotals)
        if !configDirectories.isEmpty {
            try container.encode(configDirectories, forKey: .configDirectories)
        }
        if !unreadableDirectories.isEmpty {
            try container.encode(unreadableDirectories, forKey: .unreadableDirectories)
        }
    }
}

extension TokenUsage: Codable {
    private enum CodingKeys: String, CodingKey {
        case inputTokens
        case outputTokens
        case cacheReadTokens
        case cacheCreationTokens
        case reasoningTokens
        case confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        cacheReadTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
        cacheCreationTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens)
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens)
        confidence = try container.decode(MetricConfidence.self, forKey: .confidence)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
        try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
        try container.encodeIfPresent(cacheReadTokens, forKey: .cacheReadTokens)
        try container.encodeIfPresent(cacheCreationTokens, forKey: .cacheCreationTokens)
        try container.encodeIfPresent(reasoningTokens, forKey: .reasoningTokens)
        try container.encode(confidence, forKey: .confidence)
    }
}

extension CostUsage: Codable {
    private enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        confidence = try container.decode(MetricConfidence.self, forKey: .confidence)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encode(confidence, forKey: .confidence)
    }
}

extension QuotaWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case providerID
        case type
        case used
        case limit
        case remaining
        case resetAt
        case confidence
        case source
        case label
        case bucketKey
        case observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(ProviderID.self, forKey: .providerID)
        type = try container.decode(QuotaWindowType.self, forKey: .type)
        used = try container.decodeIfPresent(Double.self, forKey: .used)
        limit = try container.decodeIfPresent(Double.self, forKey: .limit)
        remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        confidence = try container.decode(MetricConfidence.self, forKey: .confidence)
        source = try container.decode(String.self, forKey: .source)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        bucketKey = try container.decodeIfPresent(String.self, forKey: .bucketKey)
        // Absent in caches written before this field existed — decodes as nil, which the
        // routing gate treats as "unknown age", not "stale". Old cache files stay readable.
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(used, forKey: .used)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(remaining, forKey: .remaining)
        try container.encodeIfPresent(resetAt, forKey: .resetAt)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(bucketKey, forKey: .bucketKey)
        try container.encodeIfPresent(observedAt, forKey: .observedAt)
    }
}

extension ProviderWarning: Codable {
    private enum CodingKeys: String, CodingKey {
        case message
        case level
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        level = try container.decode(Level.self, forKey: .level)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(level, forKey: .level)
    }
}
