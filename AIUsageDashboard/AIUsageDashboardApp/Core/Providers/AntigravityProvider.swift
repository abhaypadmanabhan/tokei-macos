import Foundation

public actor AntigravityProvider: UsageProvider {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"

    public nonisolated var capabilities: ProviderCapabilities {
        if userDefaultsReader.bool(forKey: "antigravityOnlineQuotaEnabled") {
            return [.localLog, .quota, .providerEndpoint]
        }
        return [.localLog]
    }

    private let fileManager: FileManager
    private var calendar: Calendar
    private let now: @Sendable () -> Date
    private let stateDatabaseURL: URL
    private let conversationParser: AntigravityConversationParser
    private let parser: AntigravityStateDBParser
    private let quotaClient: AntigravityQuotaClient
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: AntigravityStateDBParser = .init(),
        conversationParser: AntigravityConversationParser = .init(),
        quotaClient: AntigravityQuotaClient? = nil,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
        self.parser = parser
        self.conversationParser = conversationParser
        self.quotaClient = quotaClient ?? AntigravityQuotaClientImpl()
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    public func detectAvailability() async -> ProviderAvailability {
        if fileManager.fileExists(atPath: stateDatabaseURL.path) { return .installed }
        return await conversationParser.hasLocalHistory() ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .authenticated : .unknown
    }

    public func updateCalendar(_ calendar: Calendar) async {
        self.calendar = calendar
        await conversationParser.updateCalendar(calendar)
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let fetchedAt = now()
        let state = fileManager.fileExists(atPath: stateDatabaseURL.path)
            ? await parser.parse(stateDatabaseURL: stateDatabaseURL)
            : AntigravityStateDBParser.ParsedState()
        let history = await conversationParser.parse()
        var quotaWindows: [QuotaWindow] = []

        if userDefaultsReader.bool(forKey: "antigravityOnlineQuotaEnabled") {
            quotaWindows = (try? await quotaClient.fetchQuotaWindows()) ?? []
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: quotaWindows,
            todayUsage: history.today,
            weekUsage: history.week,
            monthUsage: history.month,
            lifetimeUsage: history.lifetime,
            costUsage: costUsage(history, at: fetchedAt),
            warnings: warnings(from: state, hasLiveQuota: !quotaWindows.isEmpty) + history.warnings,
            lastSyncedAt: fetchedAt,
            dailyTotals: history.dailyTotals,
            dailyModelUsage: history.lifetime.totalTokens == nil ? nil : history.dailyModelUsage
        )
    }

    private func costUsage(_ history: AntigravityConversationParser.AggregateUsage, at reference: Date) -> CostUsage {
        let pricing = PricingEngine(table: PricingService.cachedTable())
        let month = calendar.dateInterval(of: .month, for: reference)
        let models = UsageAggregation.sumModels(history.dailyModelUsage.compactMap { day, models in
            guard let month, day >= month.start, day <= reference else { return nil }
            return models
        })
        let amounts = models.compactMap { pricing.cost(model: $0.key, tokens: $0.value) }
        return amounts.isEmpty ? CostUsage(confidence: .unavailable)
            : CostUsage(amount: amounts.reduce(0, +), currency: "USD", confidence: .estimated)
    }

    private func warnings(from state: AntigravityStateDBParser.ParsedState, hasLiveQuota: Bool) -> [ProviderWarning] {
        var warnings = state.warnings

        if let planName = state.planName, !planName.isEmpty {
            warnings.append(ProviderWarning(message: "Plan: \(planName)", level: .info))
        }

        // `availableCredits` is a real local number, but it is NOT the "Model Quota"
        // (per-model weekly / 5-hour limits) users see in the Antigravity app — that
        // data is fetched live from Google's backend and is not written to local
        // storage, so Tokei cannot show it offline. Surface the credits honestly and
        // say so, rather than fabricating a quota gauge from unrelated numbers.
        if let availableCredits = state.availableCredits {
            warnings.append(ProviderWarning(
                message: "Antigravity: \(availableCredits) model credits available (local).",
                level: .info
            ))
        }
        if !hasLiveQuota {
            warnings.append(ProviderWarning(
                message: "Model quota (weekly / 5-hour limits) is only shown in the Antigravity app; it is not stored locally, so Tokei can't read it offline.",
                level: .info
            ))
        }

        return warnings
    }
}

extension AntigravityProvider: CalendarAwareProvider {}
