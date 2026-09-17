import Foundation

public actor CodexProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .codex
    public let displayName: String = "OpenAI Codex"
    public let capabilities: ProviderCapabilities = [.localLog, .tokenUsage, .quota]

    private let fileManager: FileManager
    private let parser: CodexJSONLParser
    private let pricing: PricingService
    private let discoverer: any AccountDiscovering
    private let discoveryContext: DiscoveryContext
    private let now: @Sendable () -> Date
    private var identityAttribution = CodexIdentityAttribution()

    private struct AccountCollection {
        var profiles: [CodexIdentityAttribution.Profile] = []
        var aggregates: [CodexJSONLParser.AggregateUsage] = []
        var logs: [LogSource] = []
        var warnings: [ProviderWarning] = []
    }

    public init(
        fileManager: FileManager = .default,
        parser: CodexJSONLParser = .init(),
        codexDirectory: URL? = nil,
        pricing: PricingService = .shared,
        homeDirectory: URL? = nil,
        registeredDirectories: [URL] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        discoverer: any AccountDiscovering = CodexAccountDiscoverer(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.parser = parser
        self.pricing = pricing
        self.discoverer = discoverer
        self.now = now

        let home = homeDirectory ?? codexDirectory?.deletingLastPathComponent()
            ?? fileManager.homeDirectoryForCurrentUser
        let registered = codexDirectory.map { [$0] } ?? registeredDirectories
        let inherited = codexDirectory == nil
            ? environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            : nil
        self.discoveryContext = DiscoveryContext(
            home: home,
            registeredRoots: registered,
            inheritedRoot: inherited,
            fileManager: fileManager
        )
    }

    public func detectAvailability() async -> ProviderAvailability {
        ((try? discoverer.discover(context: discoveryContext)) ?? []).isEmpty
            ? .notInstalled
            : .installed
    }

    public func authenticate() async throws -> AuthStatus {
        let accounts = try discoverer.discover(context: discoveryContext)
        let hasAuth = accounts.flatMap(\.profiles).contains { profile in
            fileManager.fileExists(
                atPath: profile.root.appendingPathComponent("auth.json").path
            )
        }
        return hasAuth ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let accounts = try discoverer.discover(context: discoveryContext)
        let fetchedAt = now()
        let collected = try await collect(accounts)
        let attributedUsages = identityAttribution.attribute(
            accounts: accounts,
            profiles: collected.profiles,
            observedAt: fetchedAt
        )

        let headline = AccountQuotaDecision.headline(
            among: attributedUsages,
            providerID: id,
            now: fetchedAt
        )
        let lifetime = UsageAggregation.sum(collected.aggregates.map(\.lifetime))
        let costUsage = await costUsage(for: lifetime, logs: collected.logs)

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: headline?.account.quotaWindows ?? [],
            todayUsage: UsageAggregation.sum(collected.aggregates.map(\.today)),
            weekUsage: UsageAggregation.sum(collected.aggregates.map(\.week)),
            monthUsage: UsageAggregation.sum(collected.aggregates.map(\.month)),
            lifetimeUsage: lifetime,
            costUsage: costUsage,
            warnings: collected.warnings,
            lastSyncedAt: fetchedAt,
            dailyTotals: UsageAggregation.merge(collected.aggregates.map(\.dailyTotals)),
            hourlyTotals: UsageAggregation.merge(collected.aggregates.compactMap(\.hourlyTotals)),
            accounts: attributedUsages.isEmpty ? nil : attributedUsages,
            headlineAccountID: headline?.account.id
        )
    }

    private func collect(_ accounts: [ProviderAccount]) async throws -> AccountCollection {
        var result = AccountCollection()
        for account in accounts {
            var accountHasLogs = false
            for profile in account.profiles {
                let logs = try discoverLogSources(in: profile.root)
                accountHasLogs = accountHasLogs || !logs.isEmpty
                result.logs.append(contentsOf: logs)
                let aggregate = await parser.parse(logSources: logs)
                result.profiles.append(CodexIdentityAttribution.Profile(
                    account: account,
                    profile: profile,
                    aggregate: aggregate
                ))
                result.aggregates.append(aggregate)
                result.warnings.append(contentsOf: aggregate.warnings)
            }
            if !accountHasLogs {
                result.warnings.append(ProviderWarning(
                    message: "No Codex session logs found for \(account.label)",
                    level: .info
                ))
            }
        }
        if accounts.isEmpty {
            result.warnings.append(ProviderWarning(
                message: "No Codex session logs found",
                level: .info
            ))
        }
        return result
    }

    private func costUsage(for lifetime: TokenUsage, logs: [LogSource]) async -> CostUsage {
        guard let model = await parser.detectLatestModel(logSources: logs) else {
            return CostUsage(confidence: .unavailable)
        }
        Task { [pricing] in await pricing.refreshIfStale() }
        guard let amount = await pricing.cost(model: model, tokens: lifetime) else {
            return CostUsage(confidence: .unavailable)
        }
        return CostUsage(amount: amount, currency: "USD", confidence: .estimated)
    }

    public func discoverLogSources() async throws -> [LogSource] {
        try discoverer.discover(context: discoveryContext)
            .flatMap { try discoverLogSources(for: $0) }
            .sorted { $0.url.path < $1.url.path }
    }

    private func discoverLogSources(for account: ProviderAccount) throws -> [LogSource] {
        try account.profiles.flatMap { try discoverLogSources(in: $0.root) }
            .sorted { $0.url.path < $1.url.path }
    }

    private func discoverLogSources(in codexDirectory: URL) throws -> [LogSource] {
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sources: [LogSource] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "jsonl" else { continue }
            let values = try? file.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard values?.isRegularFile != false else { continue }
            sources.append(LogSource(
                providerID: id,
                url: file,
                sessionID: file.deletingPathExtension().lastPathComponent,
                lastModified: values?.contentModificationDate
            ))
        }
        return sources
    }

    public func updateCalendar(_ calendar: Calendar) async {
        await parser.updateCalendar(calendar)
    }

}

extension CodexProvider: CalendarAwareProvider {}
