import Foundation

public actor CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor
    public let displayName: String = "Cursor"
    public let capabilities: ProviderCapabilities = []

    public init() {}

    public func detectAvailability() async -> ProviderAvailability {
        // TODO: Detect Cursor state.vscdb.
        .unknown
    }

    public func authenticate() async throws -> AuthStatus {
        // TODO: Read cursorAuth/accessToken from state.vscdb.
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
                    type: .monthly,
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    resetAt: nil,
                    confidence: .unavailable,
                    source: "Cursor monthly budget not yet available"
                )
            ],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: [ProviderWarning(message: "Cursor provider not yet implemented; monthly-budget model only", level: .info)],
            lastSyncedAt: Date()
        )
    }
}
