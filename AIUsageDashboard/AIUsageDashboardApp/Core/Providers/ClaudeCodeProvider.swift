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
        let logs = try? await discoverLogSources()
        let usage = try? await parser.parse(logSources: logs ?? [])

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
            todayUsage: usage?.today ?? .unavailable,
            weekUsage: usage?.week ?? .unavailable,
            monthUsage: usage?.month,
            lifetimeUsage: usage?.lifetime,
            costUsage: nil,
            warnings: usage?.warnings ?? [ProviderWarning(message: "Local logs only; quotas unavailable", level: .info)],
            lastSyncedAt: Date()
        )
    }

    public func discoverLogSources() async throws -> [LogSource] {
        let home = fileManager.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects", isDirectory: true)
        var sources: [LogSource] = []

        guard let projectDirs = try? fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else {
            return sources
        }

        for projectDir in projectDirs {
            guard let files = try? fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
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
