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

    /// Installed when **any** config directory of any account exists — an account is an
    /// identity, not a directory, and its canonical directory is not guaranteed to be the one
    /// on disk. `discover()` lists `~/.claude` whether or not it exists (its identity is read
    /// from `~/.claude.json`, which sits outside it and survives `rm -rf ~/.claude`), and the
    /// default wins the canonical pick, so checking only the canonical reported "not
    /// installed" for a machine whose logs `fetchSnapshot()` was parsing correctly.
    public func detectAvailability() async -> ProviderAvailability {
        let installed = accounts.contains { account in
            account.configDirectories.contains { fileManager.fileExists(atPath: $0.path) }
        }
        return installed ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        // Claude Code local logs do not require app-level authentication.
        .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let networkEnabled = userDefaultsReader.bool(forKey: "claudeNetworkUsageEnabled")
        // Only label warnings by account when there is more than one — a single-account
        // setup shouldn't grow noise it never had.
        let multiAccount = accounts.count > 1

        var results: [AccountFetch] = []
        for account in accounts {
            results.append(
                await fetchAccount(account, networkEnabled: networkEnabled, multiAccount: multiAccount)
            )
        }

        let accountUsages = results.map(\.usage)
        let perAccountUsage = results.map(\.parsed)
        var warnings = results.flatMap(\.warnings)
        // One account authenticating is enough to say Claude is connected.
        let liveQuotaAuthenticated = results.contains { $0.authenticated }

        let headline = Self.headlineAccount(from: accountUsages)
        let quotaWindows = headline?.quotaWindows ?? Self.unavailableQuotaWindows(providerID: id)

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
            accounts: accountUsages,
            headlineAccountID: headline?.id
        )
    }

    /// Everything one account contributes to the snapshot. Accounts are independent — the
    /// only thing the loop above does with these is concatenate them — so the per-account
    /// work is a function of the account, not 80 lines of accumulator bookkeeping.
    private struct AccountFetch {
        let usage: ProviderAccountUsage
        let parsed: ClaudeJSONLParser.AggregateUsage
        let warnings: [ProviderWarning]
        let authenticated: Bool
    }

    /// This account's log files, plus what went wrong finding them.
    ///
    /// One account can own several config directories (the same Anthropic identity signed in
    /// from `~/.claude` and `~/.claude-account-2`, say). Its logs are the union of theirs,
    /// returned as one list so the parser dedupes a session copied between directories
    /// rather than counting it twice.
    private func discoverLogs(
        for account: ClaudeAccount,
        multiAccount: Bool
    ) async -> (logs: [LogSource], unreadableDirectories: [String], warnings: [ProviderWarning]) {
        var logs: [LogSource] = []
        // Directories this account owns that exist but refused to be read. They are the
        // difference between "this identity used 300 tokens" and "this identity used 300
        // tokens *that we could see*", so the row carries them and can say so.
        var unreadableDirectories: [String] = []
        var warnings: [ProviderWarning] = []

        for projectsDirectory in account.projectsDirectories {
            do {
                logs += try await Self.logSources(in: projectsDirectory, id: id, fileManager: fileManager)
            } catch {
                // Name the directory when the account owns more than one, so two failures
                // under the same label stay distinguishable. A single-directory account
                // keeps the message it always had.
                let configDirectory = projectsDirectory.deletingLastPathComponent()
                let directory = account.configDirectories.count > 1
                    ? " in \(configDirectory.lastPathComponent)"
                    : ""
                // Absent is not broken: a directory that has never run a session has no
                // `projects` folder, and `discover()` always lists `~/.claude` whether or
                // not it exists — so warning here gave every machine that has never run
                // Claude Code a permanent "Failed to discover Claude logs" (which also
                // displaced the accurate "Local logs only; quotas unavailable"). Only a
                // directory that is there and refuses to be read leaves a hole worth
                // naming.
                guard !Self.isMissing(error) else { continue }
                warnings.append(ProviderWarning(
                    message: Self.prefixed(
                        "Failed to discover Claude logs\(directory): \(error.localizedDescription)",
                        account: account, multiAccount: multiAccount
                    ),
                    level: .warning
                ))
                if !unreadableDirectories.contains(configDirectory.path) {
                    unreadableDirectories.append(configDirectory.path)
                }
            }
        }

        return (logs, unreadableDirectories, warnings)
    }

    private func fetchAccount(
        _ account: ClaudeAccount,
        networkEnabled: Bool,
        multiAccount: Bool
    ) async -> AccountFetch {
        let discovery = await discoverLogs(for: account, multiAccount: multiAccount)
        var warnings = discovery.warnings
        let logs = discovery.logs
        let unreadableDirectories = discovery.unreadableDirectories

        let parsed = await parser.parse(logSources: logs)
        warnings.append(contentsOf: parsed.warnings)

        var accountWindows = Self.unavailableQuotaWindows(providerID: id)
        var authenticated = false
        if networkEnabled {
            do {
                let liveWindows = try await liveQuotaWindows(for: account)
                if !liveWindows.isEmpty {
                    accountWindows = liveWindows
                    // A successful non-empty live-quota fetch means the OAuth usage endpoint
                    // accepted our credentials — report auth honestly instead of the blanket
                    // `.unknown`, which read as "not signed in" in the UI even while live
                    // quota was flowing.
                    authenticated = true
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

        return AccountFetch(
            usage: ProviderAccountUsage(
                id: account.id,
                label: account.label,
                quotaWindows: accountWindows,
                todayUsage: parsed.today,
                // The same daily series that goes into the provider-level merge, kept per
                // account so a surface can answer "which account is spending more" over time
                // instead of only right now.
                dailyTotals: parsed.dailyTotals,
                configDirectories: account.configDirectories.map(\.path),
                unreadableDirectories: unreadableDirectories
            ),
            parsed: parsed,
            warnings: warnings,
            authenticated: authenticated
        )
    }

    /// This identity's live quota, from the first of its config directories that answers.
    ///
    /// The happy path stays **one request**: the canonical directory is tried first and, when
    /// its credentials work, nothing else is asked. A sibling is reached only when the
    /// canonical produced nothing — its Keychain item absent (the canonical directory is not
    /// required to exist on disk), signed out, or expired. Every directory of an identity
    /// authenticates to the same Anthropic account, so the fallback re-asks the same question
    /// about the same quota rather than adding a second account's worth of load.
    private func liveQuotaWindows(for account: ClaudeAccount) async throws -> [QuotaWindow] {
        var firstFailure: Error?
        for candidate in account.credentialCandidates {
            do {
                let windows = try await usageClientFactory(candidate).fetchQuotaWindows()
                if !windows.isEmpty { return windows }
            } catch {
                // Report the canonical's failure, not the last sibling's: the fallback is an
                // internal retry, and naming a directory the user never pointed Tokei at
                // would make the warning harder to act on, not easier.
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
        return []
    }

    /// The account whose windows become the provider's headline quota: the one with the
    /// **most headroom**, i.e. the lowest peak utilization. `nil` when no account has a
    /// usable reading.
    ///
    /// Work can be sent to whichever account you like (that's what `CLAUDE_CONFIG_DIR` is
    /// for), so available capacity is the best account's — not the worst's, and not an
    /// average, which would describe no account that actually exists. Accounts with no
    /// usable reading are skipped rather than counted as 0%.
    ///
    /// Published on the snapshot as `headlineAccountID` so a surface can *name* the account
    /// the gauge belongs to without re-deriving this rule. The drill-in used to recompute
    /// "lowest peak wins" itself and then check its answer against the number on screen —
    /// which meant two definitions of the same rule, differing (the copy excluded credits
    /// windows, this does not) in a way that surfaced as the explanation silently going
    /// vague rather than as anything a test could catch.
    private static func headlineAccount(
        from accountUsages: [ProviderAccountUsage]
    ) -> ProviderAccountUsage? {
        let withReadings = accountUsages.filter { usage in
            usage.quotaWindows.contains { UtilizationEngine.usedPercent(from: $0) != nil }
        }
        // Headroom decides *within* a confidence tier, never across it. Only this account's
        // windows go on the snapshot, so choosing a stale 10% over a confirmed 50% does not
        // merely mislabel the gauge — it publishes an unroutable reading and
        // `RouteTargetPolicy` drops Claude entirely, while the account it could have used
        // sat right there. A confirmed number is worth more than a better-looking one.
        let trusted = withReadings.filter(hasRoutableReading)
        let pool = trusted.isEmpty ? withReadings : trusted
        return pool.min { peakPercent($0.quotaWindows) < peakPercent($1.quotaWindows) }
    }

    private static func hasRoutableReading(_ usage: ProviderAccountUsage) -> Bool {
        usage.quotaWindows.contains { window in
            UtilizationEngine.usedPercent(from: window) != nil
                && RouteTargetPolicy.defaultRoutableConfidences.contains(window.confidence)
        }
    }

    private static func peakPercent(_ windows: [QuotaWindow]) -> Double {
        windows.compactMap { UtilizationEngine.usedPercent(from: $0) }.max() ?? 0
    }

    /// A path that is simply not there, as opposed to one that refused to be read. Both
    /// throw from `contentsOfDirectory`; only the second means an account's numbers are
    /// incomplete.
    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
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
