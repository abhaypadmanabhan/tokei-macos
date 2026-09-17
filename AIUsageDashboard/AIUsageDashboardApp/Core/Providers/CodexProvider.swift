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
    private var attributionByRoot: [String: RootAttribution] = [:]

    private struct IdentityEpoch {
        let accountID: String
        let legacyID: String
        let label: String
        let baselineDailyUsage: [Date: TokenUsage]
        let baselineDailyTotals: [Date: Int]
        /// Nil for the identity first observed on this root. A later identity must
        /// produce a quota event at or after this refresh boundary.
        let transitionObservedAt: Date?
    }

    private struct RootAttribution {
        var currentAccountID: String
        var rawDailyUsage: [Date: TokenUsage]
        var rawDailyTotals: [Date: Int]
        var epochs: [IdentityEpoch]
    }

    private struct ProfileCollection {
        let account: ProviderAccount
        let profile: AccountProfile
        let aggregate: CodexJSONLParser.AggregateUsage
    }

    private struct AccountCollection {
        var profiles: [ProfileCollection] = []
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
        let attributedUsages = attributedUsages(
            accounts: accounts,
            profiles: collected.profiles,
            observedAt: fetchedAt
        )

        let headline = AccountQuotaDecision.headline(
            among: attributedUsages,
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
            accounts: attributedUsages.isEmpty ? nil : attributedUsages,
            headlineAccountID: headline?.account.id
        )
    }

    /// Attribute each root's raw dated totals through immutable identity epochs. Epoch
    /// baselines are always raw parser output; attributed account rows never feed back
    /// into a later refresh. This makes the sum of account rows equal the raw provider
    /// total across repeated identity switches, root regrouping, and day rollover.
    private func attributedUsages(
        accounts: [ProviderAccount],
        profiles: [ProfileCollection],
        observedAt: Date
    ) -> [ProviderAccountUsage] {
        let activeRoots = Set(profiles.map { Self.canonicalPath($0.profile.root) })
        attributionByRoot = attributionByRoot.filter { activeRoots.contains($0.key) }

        for collected in profiles {
            let root = Self.canonicalPath(collected.profile.root)
            let aggregate = collected.aggregate
            if var attribution = attributionByRoot[root] {
                if attribution.currentAccountID != collected.account.id {
                    attribution.currentAccountID = collected.account.id
                    attribution.epochs.append(IdentityEpoch(
                        accountID: collected.account.id,
                        legacyID: collected.account.legacyID,
                        label: collected.account.label,
                        baselineDailyUsage: aggregate.dailyUsage,
                        baselineDailyTotals: aggregate.dailyTotals,
                        transitionObservedAt: observedAt
                    ))
                }
                attribution.rawDailyUsage = aggregate.dailyUsage
                attribution.rawDailyTotals = aggregate.dailyTotals
                attributionByRoot[root] = attribution
            } else {
                attributionByRoot[root] = RootAttribution(
                    currentAccountID: collected.account.id,
                    rawDailyUsage: aggregate.dailyUsage,
                    rawDailyTotals: aggregate.dailyTotals,
                    epochs: [IdentityEpoch(
                        accountID: collected.account.id,
                        legacyID: collected.account.legacyID,
                        label: collected.account.label,
                        baselineDailyUsage: [:],
                        baselineDailyTotals: [:],
                        transitionObservedAt: nil
                    )]
                )
            }
        }

        var usageByIdentity: [String: [Date: TokenUsage]] = [:]
        var totalsByIdentity: [String: [Date: Int]] = [:]
        var rootsByIdentity: [String: Set<String>] = [:]
        var historicalMetadata: [String: IdentityEpoch] = [:]
        for (root, attribution) in attributionByRoot.sorted(by: { $0.key < $1.key }) {
            let allocations = Self.epochAllocations(for: attribution)
            for (index, epoch) in attribution.epochs.enumerated() {
                historicalMetadata[epoch.accountID] = historicalMetadata[epoch.accountID] ?? epoch
                rootsByIdentity[epoch.accountID, default: []].insert(root)
                for (day, usage) in allocations[index].dailyUsage {
                    if let current = usageByIdentity[epoch.accountID]?[day] {
                        usageByIdentity[epoch.accountID]?[day] = current.merging(usage)
                    } else {
                        usageByIdentity[epoch.accountID, default: [:]][day] = usage
                    }
                }
                for (day, total) in allocations[index].dailyTotals {
                    totalsByIdentity[epoch.accountID, default: [:]][day, default: 0] += total
                }
            }
        }

        let currentByIdentity = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let currentIDs = accounts.map(\.id)
        let historicalIDs = historicalMetadata.keys
            .filter { currentByIdentity[$0] == nil }
            .sorted()
        let todayStart = profiles.first?.aggregate.todayStart

        return (currentIDs + historicalIDs).compactMap { accountID in
            guard let metadata = historicalMetadata[accountID] else { return nil }
            let current = currentByIdentity[accountID]
            let dailyUsage = usageByIdentity[accountID] ?? [:]
            let todayUsage = todayStart.flatMap { dailyUsage[$0] }
                ?? UsageWindows.emptyUsage(.localParsed)
            let quota = current == nil ? nil : quotaProjection(
                profiles: profiles.filter { $0.account.id == accountID }
            )

            return ProviderAccountUsage(
                id: current?.legacyID ?? metadata.legacyID,
                accountID: accountID,
                selector: current?.preferredProfile?.selector,
                label: current?.label ?? metadata.label,
                quotaWindows: quota?.windows ?? [],
                todayUsage: todayUsage,
                dailyTotals: totalsByIdentity[accountID] ?? [:],
                configDirectories: Array(rootsByIdentity[accountID] ?? []).sorted(),
                quotaStatus: quota?.status ?? .unknown,
                quotaStatusDetail: quota?.detail
                    ?? "Historical usage from a previous Codex identity."
            )
        }
    }

    private struct QuotaProjection {
        let windows: [QuotaWindow]
        let status: AccountQuotaStatus
        let detail: String?
    }

    private func quotaProjection(profiles: [ProfileCollection]) -> QuotaProjection {
        let withWindows = profiles.filter { !$0.aggregate.quotaWindows.isEmpty }
        let attributable = withWindows.filter { collected in
            let root = Self.canonicalPath(collected.profile.root)
            guard let boundary = attributionByRoot[root]?.epochs.last?.transitionObservedAt else {
                return true
            }
            return Self.latestQuotaObservation(in: collected.aggregate.quotaWindows)
                .map { $0 >= boundary } ?? false
        }
        let selectedAttributable = Self.latestQuotaProfile(in: attributable)
        let selectedRaw = Self.latestQuotaProfile(in: withWindows)
        let windows = selectedAttributable?.aggregate.quotaWindows
            ?? selectedRaw?.aggregate.quotaWindows
            ?? []
        let hasReading = windows.contains { UtilizationEngine.usedPercent(from: $0) != nil }

        if selectedAttributable != nil, hasReading {
            return QuotaProjection(windows: windows, status: .eligible, detail: nil)
        }
        if selectedRaw != nil, hasReading {
            return QuotaProjection(
                windows: windows,
                status: .unknown,
                detail: "Awaiting a quota observation at or after the current Codex identity transition."
            )
        }
        return QuotaProjection(windows: windows, status: .noQuotaSource, detail: nil)
    }

    private static func latestQuotaProfile(
        in profiles: [ProfileCollection]
    ) -> ProfileCollection? {
        profiles.max { lhs, rhs in
            (latestQuotaObservation(in: lhs.aggregate.quotaWindows) ?? .distantPast)
                < (latestQuotaObservation(in: rhs.aggregate.quotaWindows) ?? .distantPast)
        }
    }

    private static func latestQuotaObservation(in windows: [QuotaWindow]) -> Date? {
        windows.compactMap(\.observedAt).max()
    }

    private static func canonicalPath(_ root: URL) -> String {
        root.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private struct EpochAllocation {
        var dailyUsage: [Date: TokenUsage] = [:]
        var dailyTotals: [Date: Int] = [:]
    }

    private static func epochAllocations(for attribution: RootAttribution) -> [EpochAllocation] {
        var result = Array(repeating: EpochAllocation(), count: attribution.epochs.count)
        for (day, total) in attribution.rawDailyUsage {
            let baselines = attribution.epochs.map { $0.baselineDailyUsage[day] }
            let input = allocate(total: total.inputTokens, baselines: baselines.map { $0?.inputTokens })
            let output = allocate(total: total.outputTokens, baselines: baselines.map { $0?.outputTokens })
            let cacheRead = allocate(
                total: total.cacheReadTokens,
                baselines: baselines.map { $0?.cacheReadTokens }
            )
            let cacheCreation = allocate(
                total: total.cacheCreationTokens,
                baselines: baselines.map { $0?.cacheCreationTokens }
            )
            let reasoning = allocate(
                total: total.reasoningTokens,
                baselines: baselines.map { $0?.reasoningTokens }
            )

            for index in attribution.epochs.indices {
                result[index].dailyUsage[day] = TokenUsage(
                    inputTokens: input[index],
                    outputTokens: output[index],
                    cacheReadTokens: cacheRead[index],
                    cacheCreationTokens: cacheCreation[index],
                    reasoningTokens: reasoning[index],
                    confidence: total.confidence
                )
            }
        }
        for (day, total) in attribution.rawDailyTotals {
            let allocated = allocate(
                total: total,
                baselines: attribution.epochs.map { $0.baselineDailyTotals[day] }
            )
            for index in attribution.epochs.indices {
                result[index].dailyTotals[day] = allocated[index] ?? 0
            }
        }
        return result
    }

    /// Turn raw cumulative values at each identity boundary into non-overlapping epoch
    /// deltas. The monotonic clamp also preserves conservation if a log is truncated or
    /// rewritten below an older boundary: current raw data remains the source of truth.
    private static func allocate(total: Int?, baselines: [Int?]) -> [Int?] {
        guard let total else { return Array(repeating: nil, count: baselines.count) }
        let boundedTotal = max(0, total)
        var floor = 0
        let starts = baselines.map { baseline -> Int in
            let start = min(boundedTotal, max(floor, max(0, baseline ?? 0)))
            floor = start
            return start
        }
        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : boundedTotal
            return end - starts[index]
        }
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
                result.profiles.append(ProfileCollection(
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
