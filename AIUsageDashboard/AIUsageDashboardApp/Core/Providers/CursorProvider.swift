import Foundation

public actor CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor
    public let displayName: String = "Cursor"
    public let capabilities: ProviderCapabilities = []

    private let fileManager: FileManager
    private let stateDatabaseURL: URL

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: [],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: [ProviderWarning(
                message: "Cursor metrics require dashboard auth (post-MVP)",
                level: .info
            )],
            lastSyncedAt: Date()
        )
    }
}
