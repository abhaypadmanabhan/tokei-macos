import Foundation

public actor OpencodeProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .opencode
    public let displayName: String = "opencode"
    public let capabilities: ProviderCapabilities = [.localLog, .tokenUsage, .cost]

    private let fileManager: FileManager
    private let parser: OpencodeStoreParser
    private let opencodeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        parser: OpencodeStoreParser = .init(),
        opencodeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.parser = parser
        self.opencodeDirectory = opencodeDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: opencodeDirectory.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        let auth = opencodeDirectory.appendingPathComponent("auth.json")
        return fileManager.fileExists(atPath: auth.path) ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let usage = await parser.parse(rootDirectory: opencodeDirectory)
        var warnings = usage.warnings
        if usage.sourceKind == .none {
            warnings.append(ProviderWarning(message: "No opencode messages found", level: .info))
        }

        let costUsage: CostUsage
        if usage.totalCost > 0 {
            costUsage = CostUsage(amount: usage.totalCost, currency: "USD", confidence: .providerReported)
        } else {
            costUsage = CostUsage(confidence: .unavailable)
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: [],
            todayUsage: usage.today,
            weekUsage: usage.week,
            monthUsage: usage.month,
            lifetimeUsage: usage.lifetime,
            costUsage: costUsage,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: usage.dailyTotals
        )
    }

    public func discoverLogSources() async throws -> [LogSource] {
        try await parser.discoverLogSources(rootDirectory: opencodeDirectory)
    }
}
