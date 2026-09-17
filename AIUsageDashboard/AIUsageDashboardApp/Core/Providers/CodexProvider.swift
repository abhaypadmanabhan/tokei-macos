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
    private var accountIDByRoot: [String: String] = [:]
    private var latestActiveUsageByAccountID: [String: ProviderAccountUsage] = [:]
    private var historicalUsageByAccountID: [String: ProviderAccountUsage] = [:]
    private var usageBaselineByAccountID: [String: ProviderAccountUsage] = [:]
    private var quotaObservationFloorByAccountID: [String: Date] = [:]

    private struct AccountCollection {
        var usages: [ProviderAccountUsage] = []
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
        prepareIdentityTransitions(for: accounts)
        var collected = try await collect(accounts)
        collected.usages = attributedUsages(collected.usages)

        let headline = AccountQuotaDecision.headline(
            among: collected.usages,
            providerID: id,
            now: fetchedAt
        )
        let lifetime = Self.sum(collected.aggregates.map(\.lifetime))
        let costUsage = await costUsage(for: lifetime, logs: collected.logs)

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: headline?.account.quotaWindows ?? [],
            todayUsage: Self.sum(collected.aggregates.map(\.today)),
            weekUsage: Self.sum(collected.aggregates.map(\.week)),
            monthUsage: Self.sum(collected.aggregates.map(\.month)),
            lifetimeUsage: lifetime,
            costUsage: costUsage,
            warnings: collected.warnings,
            lastSyncedAt: fetchedAt,
            dailyTotals: Self.merged(collected.aggregates.map(\.dailyTotals)),
            hourlyTotals: Self.merged(collected.aggregates.compactMap(\.hourlyTotals)),
            accounts: collected.usages.isEmpty ? nil : collected.usages,
            headlineAccountID: headline?.account.id
        )
    }

    /// A profile can keep the same logs while `auth.json` moves to a new account. The old
    /// log-derived quota is not evidence for the new identity. Freeze the old row, subtract
    /// its token baseline from the new row, and require a later rate-limit observation.
    private func prepareIdentityTransitions(for accounts: [ProviderAccount]) {
        var transitions: [(oldID: String, newID: String)] = []
        for account in accounts {
            historicalUsageByAccountID.removeValue(forKey: account.id)
            for profile in account.profiles {
                let root = profile.root.resolvingSymlinksInPath().standardizedFileURL.path
                if let oldID = accountIDByRoot[root], oldID != account.id {
                    transitions.append((oldID: oldID, newID: account.id))
                }
                accountIDByRoot[root] = account.id
            }
        }

        for transition in transitions {
            guard let oldUsage = latestActiveUsageByAccountID[transition.oldID] else { continue }
            historicalUsageByAccountID[transition.oldID] = Self.historicalUsage(oldUsage)
            usageBaselineByAccountID[transition.newID] = oldUsage
            if let observation = Self.latestQuotaObservation(in: oldUsage) {
                quotaObservationFloorByAccountID[transition.newID] = observation
            }
        }
    }

    private func attributedUsages(_ rawUsages: [ProviderAccountUsage]) -> [ProviderAccountUsage] {
        let active = rawUsages.map { usage -> ProviderAccountUsage in
            let accountID = usage.accountID ?? usage.id
            let baseline = usageBaselineByAccountID[accountID]
            let floor = quotaObservationFloorByAccountID[accountID]
            let latestObservation = Self.latestQuotaObservation(in: usage)
            let quotaIsAttributable = floor.map { floor in
                latestObservation.map { $0 > floor } ?? false
            } ?? true
            if quotaIsAttributable {
                quotaObservationFloorByAccountID.removeValue(forKey: accountID)
            }

            return ProviderAccountUsage(
                id: usage.id,
                accountID: usage.accountID,
                selector: usage.selector,
                label: usage.label,
                quotaWindows: usage.quotaWindows,
                todayUsage: baseline.map { Self.subtract(usage.todayUsage, baseline: $0.todayUsage) }
                    ?? usage.todayUsage,
                dailyTotals: baseline.map { Self.subtract(usage.dailyTotals, baseline: $0.dailyTotals) }
                    ?? usage.dailyTotals,
                configDirectories: usage.configDirectories,
                unreadableDirectories: usage.unreadableDirectories,
                quotaStatus: quotaIsAttributable ? usage.quotaStatus : .unknown,
                quotaStatusDetail: quotaIsAttributable
                    ? usage.quotaStatusDetail
                    : "Awaiting a quota observation for the current Codex identity."
            )
        }

        latestActiveUsageByAccountID = Dictionary(
            uniqueKeysWithValues: active.map { (($0.accountID ?? $0.id), $0) }
        )
        let activeIDs = Set(latestActiveUsageByAccountID.keys)
        let historical = historicalUsageByAccountID
            .filter { !activeIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map(\.value)
        return active + historical
    }

    private static func historicalUsage(_ usage: ProviderAccountUsage) -> ProviderAccountUsage {
        ProviderAccountUsage(
            id: usage.id,
            accountID: usage.accountID,
            selector: nil,
            label: usage.label,
            quotaWindows: [],
            todayUsage: usage.todayUsage,
            dailyTotals: usage.dailyTotals,
            configDirectories: usage.configDirectories,
            unreadableDirectories: usage.unreadableDirectories,
            quotaStatus: .unknown,
            quotaStatusDetail: "Historical usage from a previous Codex identity."
        )
    }

    private static func latestQuotaObservation(in usage: ProviderAccountUsage) -> Date? {
        usage.quotaWindows.compactMap(\.observedAt).max()
    }

    private static func subtract(_ usage: TokenUsage, baseline: TokenUsage) -> TokenUsage {
        func difference(_ current: Int?, _ old: Int?) -> Int? {
            guard current != nil || old != nil else { return nil }
            return max(0, (current ?? 0) - (old ?? 0))
        }
        return TokenUsage(
            inputTokens: difference(usage.inputTokens, baseline.inputTokens),
            outputTokens: difference(usage.outputTokens, baseline.outputTokens),
            cacheReadTokens: difference(usage.cacheReadTokens, baseline.cacheReadTokens),
            cacheCreationTokens: difference(usage.cacheCreationTokens, baseline.cacheCreationTokens),
            reasoningTokens: difference(usage.reasoningTokens, baseline.reasoningTokens),
            confidence: usage.confidence
        )
    }

    private static func subtract(
        _ totals: [Date: Int]?,
        baseline: [Date: Int]?
    ) -> [Date: Int]? {
        guard let totals else { return nil }
        return totals.reduce(into: [Date: Int]()) { result, entry in
            let value = max(0, entry.value - (baseline?[entry.key] ?? 0))
            if value > 0 { result[entry.key] = value }
        }
    }

    private func collect(_ accounts: [ProviderAccount]) async throws -> AccountCollection {
        var result = AccountCollection()
        for account in accounts {
            let logs = try discoverLogSources(for: account)
            result.logs.append(contentsOf: logs)
            let usage = await parser.parse(logSources: logs)
            result.aggregates.append(usage)
            result.warnings.append(contentsOf: usage.warnings)
            if logs.isEmpty {
                result.warnings.append(ProviderWarning(
                    message: "No Codex session logs found for \(account.label)",
                    level: .info
                ))
            }
            let quotaStatus: AccountQuotaStatus = usage.quotaWindows.contains {
                UtilizationEngine.usedPercent(from: $0) != nil
            } ? .eligible : .noQuotaSource
            result.usages.append(ProviderAccountUsage(
                id: account.legacyID,
                accountID: account.id,
                selector: account.preferredProfile?.selector,
                label: account.label,
                quotaWindows: usage.quotaWindows,
                todayUsage: usage.today,
                dailyTotals: usage.dailyTotals,
                configDirectories: account.profiles.map { $0.root.path },
                quotaStatus: quotaStatus
            ))
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

    private static func sum(_ usages: [TokenUsage]) -> TokenUsage {
        func total(_ field: (TokenUsage) -> Int?) -> Int? {
            let values = usages.compactMap(field)
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        return TokenUsage(
            inputTokens: total(\.inputTokens),
            outputTokens: total(\.outputTokens),
            cacheReadTokens: total(\.cacheReadTokens),
            cacheCreationTokens: total(\.cacheCreationTokens),
            reasoningTokens: total(\.reasoningTokens),
            confidence: usages.first { $0.totalTokens != nil }?.confidence ?? .unavailable
        )
    }

    private static func merged(_ totals: [[Date: Int]]) -> [Date: Int]? {
        guard !totals.isEmpty else { return nil }
        return totals.reduce(into: [Date: Int]()) {
            $0.merge($1, uniquingKeysWith: +)
        }
    }
}

extension CodexProvider: CalendarAwareProvider {}
