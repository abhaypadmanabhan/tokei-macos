import Foundation

public actor ClaudeCodeProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .claudeCode
    public let displayName: String = "Claude Code"
    public let capabilities: ProviderCapabilities = [.localLog, .tokenUsage]

    private let fileManager: FileManager
    private let parser: ClaudeJSONLParser

    public init(fileManager: FileManager = .default, parser: ClaudeJSONLParser = .init()) {
        self.fileManager = fileManager
        self.parser = parser
    }

    public func detectAvailability() async -> ProviderAvailability {
        let home = fileManager.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        return fileManager.fileExists(atPath: claudeDir.path) ? .installed : .notInstalled
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

        if warnings.isEmpty {
            warnings.append(ProviderWarning(message: "Local logs only; quotas unavailable", level: .info))
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: .unknown,
            quotaWindows: [
                QuotaWindow(
                    providerID: id,
                    type: .session,
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    resetAt: nil,
                    confidence: .unavailable,
                    source: "Claude session limits not available from local logs"
                ),
                QuotaWindow(
                    providerID: id,
                    type: .weekly,
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    resetAt: nil,
                    confidence: .unavailable,
                    source: "Claude weekly limits not available from local logs"
                )
            ],
            todayUsage: usage.today,
            weekUsage: usage.week,
            monthUsage: usage.month,
            lifetimeUsage: usage.lifetime,
            costUsage: nil,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: usage.dailyTotals
        )
    }

    public func discoverLogSources() async throws -> [LogSource] {
        let home = fileManager.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects", isDirectory: true)
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
}
