import Foundation

/// Foundation-only public route contract, also compiled into the standalone helper.
/// No selectors, local paths or raw account identifiers enter this block.
public struct AgentRoute: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let rows: [AgentRouteRow]
    public let unknown: [AgentRouteUnknown]

    public init(generatedAt: Date, rows: [AgentRouteRow], unknown: [AgentRouteUnknown]) {
        self.generatedAt = generatedAt
        self.rows = rows
        self.unknown = unknown
    }
}

public struct AgentRouteRow: Codable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let providerName: String
    public let accountLabel: String?
    public let windowType: String
    public let windowLabel: String?
    public let remainingPercent: Double
    public let resetAt: Date?
    public let secondsToReset: TimeInterval?
    public let paceState: String?
    public let disposition: String
    public let reason: String
    public let validUntil: Date
    public let expiringAt: Date?

    public init(id: String, provider: String, providerName: String, accountLabel: String?,
                windowType: String, windowLabel: String?, remainingPercent: Double,
                resetAt: Date?, secondsToReset: TimeInterval?, paceState: String?,
                disposition: String, reason: String, validUntil: Date, expiringAt: Date?) {
        self.id = id
        self.provider = provider
        self.providerName = providerName
        self.accountLabel = accountLabel
        self.windowType = windowType
        self.windowLabel = windowLabel
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
        self.secondsToReset = secondsToReset
        self.paceState = paceState
        self.disposition = disposition
        self.reason = reason
        self.validUntil = validUntil
        self.expiringAt = expiringAt
    }
}

public struct AgentRouteUnknown: Codable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let accountLabel: String?
    public let reason: String

    public init(id: String, provider: String, accountLabel: String?, reason: String) {
        self.id = id
        self.provider = provider
        self.accountLabel = accountLabel
        self.reason = reason
    }
}

// The public tool target compiles AgentRoute.swift directly, so Core-only projection
// lives in RoutePlan+Agent.swift instead of a canImport-dependent build path.
