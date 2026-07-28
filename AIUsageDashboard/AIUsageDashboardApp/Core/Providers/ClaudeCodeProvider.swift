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
    private let accounts: [ClaudeAccount]
    private let usageClientFactory: @Sendable (ClaudeAccount) -> ClaudeUsageClient
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    /// Multi-account init. Claude Code supports several signed-in accounts on one machine
    /// (`CLAUDE_CONFIG_DIR`), each with its own logs, credentials, and quota. Tokei used to
    /// read only `~/.claude` and present that one account's numbers as the whole picture.
    public init(
        fileManager: FileManager = .default,
        parser: ClaudeJSONLParser = .init(),
        accounts: [ClaudeAccount],
        usageClientFactory: @escaping @Sendable (ClaudeAccount) -> ClaudeUsageClient = {
            ClaudeUsageClientImpl(account: $0)
        },
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.parser = parser
        // Never zero accounts: an empty list would silently report "Claude not installed".
        self.accounts = accounts.isEmpty ? ClaudeAccount.discover() : accounts
        self.usageClientFactory = usageClientFactory
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    /// Single-account init, kept for callers (and tests) that address one directory and
    /// inject one client directly.
    public init(
        fileManager: FileManager = .default,
        parser: ClaudeJSONLParser = .init(),
        claudeDirectoryURL: URL? = nil,
        usageClient: ClaudeUsageClient? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let home = fileManager.homeDirectoryForCurrentUser
        let directory = claudeDirectoryURL ?? home.appendingPathComponent(".claude", isDirectory: true)
        let account = ClaudeAccount(configDirectory: directory, home: home)
        let client = usageClient
        self.init(
            fileManager: fileManager,
            parser: parser,
            accounts: [account],
            usageClientFactory: { account in client ?? ClaudeUsageClientImpl(account: account) },
            userDefaults: userDefaults
        )
    }

    public func detectAvailability() async -> ProviderAvailability {
        accounts.contains { fileManager.fileExists(atPath: $0.configDirectory.path) }
            ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        // Claude Code local logs do not require app-level authentication.
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        var warnings: [ProviderWarning] = []
        var accountUsages: [ProviderAccountUsage] = []
        var perAccountUsage: [ClaudeJSONLParser.AggregateUsage] = []
        var liveQuotaAuthenticated = false
        let networkEnabled = userDefaultsReader.bool(forKey: "claudeNetworkUsageEnabled")
        // Only label warnings by account when there is more than one — a single-account
        // setup shouldn't grow noise it never had.
        let multiAccount = accounts.count > 1

        for account in accounts {
            // One account can own several config directories (the same Anthropic identity
            // signed in from `~/.claude` and `~/.claude-account-2`, say). Its logs are the
            // union of theirs, parsed in a single call so a record present in both — a
            // session copied between directories — is deduped rather than counted twice.
            var logs: [LogSource] = []
            for projectsDirectory in account.projectsDirectories {
                do {
                    logs += try await Self.logSources(in: projectsDirectory, id: id, fileManager: fileManager)
                } catch {
                    // Name the directory when the account owns more than one, so two
                    // failures under the same label stay distinguishable. A single-directory
                    // account keeps the message it always had.
                    let directory = account.configDirectories.count > 1
                        ? " in \(projectsDirectory.deletingLastPathComponent().lastPathComponent)"
                        : ""
                    warnings.append(ProviderWarning(
                        message: Self.prefixed(
                            "Failed to discover Claude logs\(directory): \(error.localizedDescription)",
                            account: account, multiAccount: multiAccount
                        ),
                        level: .warning
                    ))
                }
            }

            let usage = await parser.parse(logSources: logs)
            warnings.append(contentsOf: usage.warnings)
            perAccountUsage.append(usage)

            var accountWindows = Self.unavailableQuotaWindows(providerID: id)
            if networkEnabled {
                do {
                    let liveWindows = try await usageClientFactory(account).fetchQuotaWindows()
                    if !liveWindows.isEmpty {
                        accountWindows = liveWindows
                        // A successful non-empty live-quota fetch means the OAuth usage
                        // endpoint accepted our credentials — report auth honestly
                        // instead of the blanket `.unknown` (which read as "not signed
                        // in" in the UI even while live quota was flowing). One account
                        // authenticating is enough to say Claude is connected.
                        liveQuotaAuthenticated = true
                    }
                } catch {
                    warnings.append(ProviderWarning(
                        message: Self.prefixed(
                            "Claude online usage request failed: \(error.localizedDescription). Falling back to local logs only.",
                            account: account, multiAccount: multiAccount
                        ),
                        level: .warning
                    ))
                }
            }

            accountUsages.append(ProviderAccountUsage(
                id: account.id,
                label: account.label,
                quotaWindows: accountWindows,
                todayUsage: usage.today
            ))
        }

        let quotaWindows = Self.headlineQuotaWindows(from: accountUsages, providerID: id)

        if warnings.isEmpty && quotaWindows.allSatisfy({ $0.confidence == .unavailable }) {
            warnings.append(ProviderWarning(message: "Local logs only; quotas unavailable", level: .info))
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: liveQuotaAuthenticated ? .authenticated : .unknown,
            quotaWindows: quotaWindows,
            todayUsage: Self.sum(perAccountUsage.map(\.today)),
            weekUsage: Self.sum(perAccountUsage.map(\.week)),
            monthUsage: Self.sum(perAccountUsage.map(\.month)),
            lifetimeUsage: Self.sum(perAccountUsage.map(\.lifetime)),
            costUsage: nil,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: Self.merged(perAccountUsage.map(\.dailyTotals)),
            hourlyTotals: Self.merged(perAccountUsage.compactMap(\.hourlyTotals)),
            accounts: accountUsages
        )
    }

    /// The quota the provider reports as its headline: the windows of the account with the
    /// **most headroom**, i.e. the lowest peak utilization.
    ///
    /// Work can be sent to whichever account you like (that's what `CLAUDE_CONFIG_DIR` is
    /// for), so available capacity is the best account's — not the worst's, and not an
    /// average, which would describe no account that actually exists. Accounts with no
    /// usable reading are skipped rather than counted as 0%.
    private static func headlineQuotaWindows(
        from accountUsages: [ProviderAccountUsage],
        providerID: ProviderID
    ) -> [QuotaWindow] {
        let withReadings = accountUsages.filter { usage in
            usage.quotaWindows.contains { UtilizationEngine.usedPercent(from: $0) != nil }
        }
        guard !withReadings.isEmpty else { return unavailableQuotaWindows(providerID: providerID) }

        let best = withReadings.min { lhs, rhs in
            peakPercent(lhs.quotaWindows) < peakPercent(rhs.quotaWindows)
        }
        return best?.quotaWindows ?? unavailableQuotaWindows(providerID: providerID)
    }

    private static func peakPercent(_ windows: [QuotaWindow]) -> Double {
        windows.compactMap { UtilizationEngine.usedPercent(from: $0) }.max() ?? 0
    }

    private static func prefixed(_ message: String, account: ClaudeAccount, multiAccount: Bool) -> String {
        multiAccount ? "[\(account.label)] \(message)" : message
    }

    /// Token totals sum across accounts — "how much work did I do on Claude" spans every
    /// account. A field stays `nil` only when *no* account reported it, so "unavailable"
    /// isn't silently turned into a zero.
    private static func sum(_ usages: [TokenUsage]) -> TokenUsage {
        func total(_ field: (TokenUsage) -> Int?) -> Int? {
            let values = usages.compactMap(field)
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        // Take the confidence from an account that actually contributed numbers. Using
        // `usages.first` would report `.unavailable` whenever the first account happened
        // to have no logs, mislabelling a total that other accounts really did measure.
        let contributing = usages.first { $0.totalTokens != nil }
        return TokenUsage(
            inputTokens: total(\.inputTokens),
            outputTokens: total(\.outputTokens),
            cacheReadTokens: total(\.cacheReadTokens),
            cacheCreationTokens: total(\.cacheCreationTokens),
            reasoningTokens: total(\.reasoningTokens),
            confidence: contributing?.confidence ?? .unavailable
        )
    }

    private static func sum(_ usages: [TokenUsage?]) -> TokenUsage? {
        let present = usages.compactMap { $0 }
        return present.isEmpty ? nil : sum(present)
    }

    private static func merged(_ totals: [[Date: Int]]) -> [Date: Int]? {
        guard !totals.isEmpty else { return nil }
        return totals.reduce(into: [Date: Int]()) { merged, next in
            merged.merge(next, uniquingKeysWith: +)
        }
    }

    /// Every account's log sources, unioned — callers (file watching, log counts) want all
    /// of them.
    ///
    /// Follows the `LocalLogProvider` partial-failure contract: one unreadable account is
    /// absorbed (the others' sessions are still worth watching), but if **every** account
    /// that actually exists fails, the first error is rethrown. Returning `[]` there would
    /// make a machine whose log directories are all broken look exactly like one that simply
    /// has no sessions yet — the regression introduced when this method started unioning
    /// with `try?`. `fetchSnapshot` does not go through here; it warns per account instead.
    ///
    /// An account whose `projects` directory does not exist is **absent, not broken**, and is
    /// skipped without counting as a failure. `ClaudeAccount.discover()` always manufactures
    /// the default `~/.claude` entry whether or not that directory exists, so on a machine
    /// that never installed Claude Code every account is synthetic — and Tokei tracks eight
    /// tools, so that is an ordinary state, not an error.
    public func discoverLogSources() async throws -> [LogSource] {
        var sources: [LogSource] = []
        var failures: [Error] = []
        var existingDirectories = 0
        // The unit here is the config directory, not the account: one identity can own
        // several, and one of them being broken says nothing about the others.
        for projectsDirectory in accounts.flatMap(\.projectsDirectories) {
            guard fileManager.fileExists(atPath: projectsDirectory.path) else { continue }
            existingDirectories += 1
            do {
                sources.append(contentsOf: try await Self.logSources(
                    in: projectsDirectory, id: id, fileManager: fileManager
                ))
            } catch {
                failures.append(error)
            }
        }
        if let failure = failures.first, failures.count == existingDirectories {
            throw failure
        }
        return sources
    }

    private static func logSources(
        in projectsDir: URL,
        id: ProviderID,
        fileManager: FileManager
    ) async throws -> [LogSource] {
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
