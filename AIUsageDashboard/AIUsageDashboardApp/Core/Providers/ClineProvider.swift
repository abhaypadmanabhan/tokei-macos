import Foundation

public actor ClineProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .cline
    public let displayName: String = "Cline"
    public let capabilities: ProviderCapabilities = [.localLog, .tokenUsage, .cost]

    private let fileManager: FileManager
    private let parser: ClineMessagesParser
    private let clineDirectory: URL

    public init(
        fileManager: FileManager = .default,
        parser: ClineMessagesParser = .init(),
        clineDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.parser = parser
        self.clineDirectory = clineDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cline", isDirectory: true)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: clineDirectory.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        var warnings: [ProviderWarning] = []
        let logs: [LogSource]
        do {
            logs = try await discoverLogSources()
        } catch {
            warnings.append(ProviderWarning(
                message: "Failed to discover Cline logs: \(error.localizedDescription)",
                level: .warning
            ))
            logs = []
        }

        let usage = await parser.parse(logSources: logs)
        warnings.append(contentsOf: usage.warnings)
        if logs.isEmpty {
            warnings.append(ProviderWarning(message: "No Cline session logs found", level: .info))
        }

        let costUsage = CostUsage(
            amount: usage.lifetime.totalTokens != nil ? usage.totalCost : nil,
            currency: usage.lifetime.totalTokens != nil ? "USD" : nil,
            confidence: usage.lifetime.totalTokens != nil ? .localParsed : .unavailable
        )

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
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
            todayUsage: usage.today,
            weekUsage: usage.week,
            monthUsage: usage.month,
            lifetimeUsage: usage.lifetime,
            costUsage: costUsage,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: usage.dailyTotals,
            hourlyTotals: usage.hourlyTotals
        )
    }

    public func discoverLogSources() async throws -> [LogSource] {
        let sessionsDirectory = clineDirectory
            .appendingPathComponent("data/sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        guard let sessionDirs = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [LogSource] = []
        for sessionDir in sessionDirs {
            let values = try? sessionDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let sessionID = sessionDir.lastPathComponent
            let messagesFile = sessionDir.appendingPathComponent("\(sessionID).messages.json")
            guard fileManager.fileExists(atPath: messagesFile.path) else { continue }

            let fileValues = try? messagesFile.resourceValues(forKeys: [.contentModificationDateKey])
            sources.append(LogSource(
                providerID: id,
                url: messagesFile,
                sessionID: sessionID,
                lastModified: fileValues?.contentModificationDate
            ))
        }

        return sources.sorted { $0.url.path < $1.url.path }
    }
}
