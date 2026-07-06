import Foundation

public actor CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor
    public let displayName: String = "Cursor"
    public let capabilities: ProviderCapabilities = []

    private let fileManager: FileManager
    private let stateDatabaseURL: URL
    private let parser: CursorStateDBParser

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: CursorStateDBParser = .init()
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        self.parser = parser
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let usage = await parser.parse(stateDatabaseURL: stateDatabaseURL)

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: [],
            todayUsage: usage.today,
            weekUsage: usage.week,
            monthUsage: usage.month,
            lifetimeUsage: usage.lifetime,
            costUsage: nil,
            warnings: usage.warnings,
            lastSyncedAt: Date(),
            dailyTotals: usage.dailyTotals.isEmpty ? nil : usage.dailyTotals
        )
    }
}
