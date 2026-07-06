import Foundation

public actor ClineProvider: UsageProvider {
    public let id: ProviderID = .cline
    public let displayName: String = "Cline"
    public let capabilities: ProviderCapabilities = []

    public init() {}

    public func detectAvailability() async -> ProviderAvailability {
        // TODO: Detect local Cline extension state or web dashboard reachability.
        .unknown
    }

    public func authenticate() async throws -> AuthStatus {
        // TODO: Validate web session/cookie.
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: .unknown,
            quotaWindows: [
                QuotaWindow(
                    providerID: id,
                    type: .credits,
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    resetAt: nil,
                    confidence: .unavailable,
                    source: "Cline credits not yet available"
                )
            ],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: CostUsage(amount: nil, currency: nil, confidence: .unavailable),
            warnings: [ProviderWarning(message: "Cline provider not yet implemented", level: .info)],
            lastSyncedAt: Date()
        )
    }
}
