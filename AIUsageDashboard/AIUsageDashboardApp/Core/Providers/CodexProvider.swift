import Foundation

public actor CodexProvider: UsageProvider {
    public let id: ProviderID = .codex
    public let displayName: String = "OpenAI Codex"
    public let capabilities: ProviderCapabilities = []

    public init() {}

    public func detectAvailability() async -> ProviderAvailability {
        // TODO: Detect ~/.codex directory or Codex auth/config.
        .unknown
    }

    public func authenticate() async throws -> AuthStatus {
        // TODO: Read ~/.codex/auth.json and validate token.
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
            warnings: [ProviderWarning(message: "Codex provider not yet implemented", level: .info)],
            lastSyncedAt: Date()
        )
    }
}
