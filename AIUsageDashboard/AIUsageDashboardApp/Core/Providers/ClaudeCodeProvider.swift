import Foundation

public actor ClaudeCodeProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .claudeCode
    public let displayName: String = "Claude Code"

    public nonisolated var capabilities: ProviderCapabilities {
        if userDefaultsReader.bool(forKey: "claudeNetworkUsageEnabled") {
            return [.localLog, .tokenUsage, .quota, .providerEndpoint]
        }
        return [.localLog, .tokenUsage]
    }

    private let fileManager: FileManager
    private let parser: ClaudeJSONLParser
    private let claudeDirectoryURL: URL
    private let usageClient: ClaudeUsageClient
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        parser: ClaudeJSONLParser = .init(),
        claudeDirectoryURL: URL? = nil,
        usageClient: ClaudeUsageClient? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.parser = parser
        self.claudeDirectoryURL = claudeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        self.usageClient = usageClient ?? ClaudeUsageClientImpl()
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: claudeDirectoryURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        // Claude Code local logs do not require app-level authentication.
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        var warnings: [ProviderWarning] = []
        let logs: [LogSource]
        do {
            logs = try await discoverLogSources()
        } catch {
            warnings.append(ProviderWarning(
                message: "Failed to discover Claude logs: \(error.localizedDescription)",
                level: .warning
            ))
            logs = []
        }

        let usage = await parser.parse(logSources: logs)
        warnings.append(contentsOf: usage.warnings)

        var quotaWindows = Self.unavailableQuotaWindows(providerID: id)
        if userDefaultsReader.bool(forKey: "claudeNetworkUsageEnabled") {
            do {
                let liveWindows = try await usageClient.fetchQuotaWindows()
                if !liveWindows.isEmpty {
                    quotaWindows = liveWindows
                }
            } catch {
                warnings.append(ProviderWarning(
                    message: "Claude online usage request failed: \(error.localizedDescription). Falling back to local logs only.",
                    level: .warning
                ))
            }
        }

        if warnings.isEmpty && quotaWindows.allSatisfy({ $0.confidence == .unavailable }) {
            warnings.append(ProviderWarning(message: "Local logs only; quotas unavailable", level: .info))
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: .unknown,
            quotaWindows: quotaWindows,
            todayUsage: usage.today,
            weekUsage: usage.week,
            monthUsage: usage.month,
            lifetimeUsage: usage.lifetime,
            costUsage: nil,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: usage.dailyTotals,
            hourlyTotals: usage.hourlyTotals
        )
    }

    public func discoverLogSources() async throws -> [LogSource] {
        let projectsDir = claudeDirectoryURL.appendingPathComponent("projects", isDirectory: true)
        var sources: [LogSource] = []

        let projectDirs = try fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey])

        for projectDir in projectDirs {
            // Skip stray files like .DS_Store — only project directories hold session logs.
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = try fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
            for file in files where file.pathExtension == "jsonl" {
                let sessionID = file.deletingPathExtension().lastPathComponent
                let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                sources.append(LogSource(
                    providerID: id,
                    url: file,
                    sessionID: sessionID,
                    lastModified: modificationDate
                ))
            }
        }

        return sources
    }

    private static func unavailableQuotaWindows(providerID: ProviderID) -> [QuotaWindow] {
        [
            QuotaWindow(
                providerID: providerID,
                type: .session,
                used: nil,
                limit: nil,
                remaining: nil,
                resetAt: nil,
                confidence: .unavailable,
                source: "Claude session limits not available from local logs"
            ),
            QuotaWindow(
                providerID: providerID,
                type: .weekly,
                used: nil,
                limit: nil,
                remaining: nil,
                resetAt: nil,
                confidence: .unavailable,
                source: "Claude weekly limits not available from local logs"
            )
        ]
    }
}
