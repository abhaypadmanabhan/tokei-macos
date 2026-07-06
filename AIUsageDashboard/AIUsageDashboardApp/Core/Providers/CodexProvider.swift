import Foundation

public actor CodexProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .codex
    public let displayName: String = "OpenAI Codex"
    public let capabilities: ProviderCapabilities = [.localLog, .tokenUsage, .quota]

    private let fileManager: FileManager
    private let parser: CodexJSONLParser
    private let codexDirectory: URL

    public init(
        fileManager: FileManager = .default,
        parser: CodexJSONLParser = .init(),
        codexDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.parser = parser
        self.codexDirectory = codexDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: codexDirectory.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        let auth = codexDirectory.appendingPathComponent("auth.json")
        return fileManager.fileExists(atPath: auth.path) ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        var warnings: [ProviderWarning] = []
        let logs: [LogSource]
        do {
            logs = try await discoverLogSources()
        } catch {
            warnings.append(ProviderWarning(
                message: "Failed to discover Codex logs: \(error.localizedDescription)",
                level: .warning
            ))
            logs = []
        }

        let usage = await parser.parse(logSources: logs)
        warnings.append(contentsOf: usage.warnings)
        if logs.isEmpty {
            warnings.append(ProviderWarning(message: "No Codex session logs found", level: .info))
        }

        let costUsage = await costUsage(for: usage.lifetime, logs: logs)

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: usage.quotaWindows,
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

    /// Estimates lifetime cost from `CodexPricing`'s static table, keyed by the most
    /// recently configured model found in the logs. No pricing row for that model
    /// (including model slugs newer than the table) yields `.unavailable`, never a
    /// guessed number.
    ///
    /// Note: this prices the *entire* `lifetime` aggregate at that one model's rate,
    /// not just tokens generated under it — a user who switched models mid-history
    /// will see their whole total skew toward the current model's price.
    private func costUsage(for lifetime: TokenUsage, logs: [LogSource]) async -> CostUsage {
        guard let model = await parser.detectLatestModel(logSources: logs),
              let amount = CodexPricing.estimateCost(tokens: lifetime, model: model) else {
            return CostUsage(confidence: .unavailable)
        }
        return CostUsage(amount: amount, currency: "USD", confidence: .estimated)
    }

    public func discoverLogSources() async throws -> [LogSource] {
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [LogSource] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "jsonl" else { continue }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            sources.append(LogSource(
                providerID: id,
                url: file,
                sessionID: file.deletingPathExtension().lastPathComponent,
                lastModified: values?.contentModificationDate
            ))
        }

        return sources.sorted { $0.url.path < $1.url.path }
    }
}
