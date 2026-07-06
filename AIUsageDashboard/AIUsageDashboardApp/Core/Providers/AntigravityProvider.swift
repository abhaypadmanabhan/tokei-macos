import Foundation

public actor AntigravityProvider: UsageProvider {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"
    public let capabilities: ProviderCapabilities = []

    public init() {}

    public func detectAvailability() async -> ProviderAvailability {
        // TODO: Research local logs/config and app endpoints.
        .unknown
    }

    public func authenticate() async throws -> AuthStatus {
        // TODO: Determine auth model.
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: .unknown,
            quotaWindows: [],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: [
                ProviderWarning(message: "Antigravity provider is a skeleton; no implementation yet", level: .info),
                ProviderWarning(message: "Research TODO: local logs, web endpoints, per-model quota", level: .info)
            ],
            lastSyncedAt: Date()
        )
    }
}
