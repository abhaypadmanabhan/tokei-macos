import Foundation

public actor CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor
    public let displayName: String = "Cursor"

    public nonisolated var capabilities: ProviderCapabilities {
        if userDefaultsReader.bool(forKey: "cursorNetworkUsageEnabled") {
            return [.localLog, .quota, .tokenUsage, .providerEndpoint]
        }
        return [.localLog]
    }

    private let fileManager: FileManager
    private let stateDatabaseURL: URL
    private let parser: CursorStateDBParser
    private let usageClient: CursorUsageClient
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: CursorStateDBParser = .init(),
        usageClient: CursorUsageClient? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        self.parser = parser
        self.usageClient = usageClient ?? CursorUsageClientImpl()
        self.calendar = calendar
        self.now = now
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)
        return state.isAuthenticated ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)
        var warnings = state.warnings

        // Offline baseline: the state DB carries only accepted code-line counts, never
        // token counts. These stay as the fallback if the online path is off or fails.
        var quotaWindows: [QuotaWindow] = []
        var todayUsage: TokenUsage = .unavailable
        var weekUsage: TokenUsage = .unavailable
        var monthUsage: TokenUsage?
        var lifetimeUsage: TokenUsage?
        var costUsage: CostUsage?
        var dailyTotals: [Date: Int]? = state.acceptedLinesByDate.isEmpty
            ? nil : state.acceptedLinesByDate

        if userDefaultsReader.bool(forKey: "cursorNetworkUsageEnabled") {
            switch await fetchOnlineUsage() {
            case .success(let online):
                // Real token usage supersedes the offline code-line stats.
                todayUsage = online.today
                weekUsage = online.week
                monthUsage = online.month
                lifetimeUsage = nil // the export may not span all history — don't claim lifetime.
                costUsage = online.cost
                if !online.dailyTotals.isEmpty { dailyTotals = online.dailyTotals }
                if let summary = online.summary, let percent = summary.usedPercent {
                    quotaWindows = [QuotaWindow(
                        providerID: id,
                        type: .monthly,
                        used: percent,
                        limit: 100,
                        remaining: max(0, 100 - percent),
                        resetAt: summary.resetAt,
                        confidence: .providerReported,
                        source: "cursor.com/api/usage-summary",
                        label: state.planLabel ?? summary.membershipType
                    )]
                }
            case .missingSession:
                warnings.append(ProviderWarning(
                    message: "Cursor online usage is enabled but no Cursor session could be read.",
                    level: .warning
                ))
            case .failure(let message):
                warnings.append(ProviderWarning(
                    message: "Cursor online usage request failed: \(message). Falling back to offline data.",
                    level: .warning
                ))
            }
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: state.isAuthenticated ? .authenticated : .unauthenticated,
            quotaWindows: quotaWindows,
            todayUsage: todayUsage,
            weekUsage: weekUsage,
            monthUsage: monthUsage,
            lifetimeUsage: lifetimeUsage,
            costUsage: costUsage,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: dailyTotals
        )
    }

    // MARK: - Online usage

    private enum OnlineFetch {
        case success(OnlineUsage)
        case missingSession
        case failure(String)
    }

    private struct OnlineUsage {
        let today: TokenUsage
        let week: TokenUsage
        let month: TokenUsage
        let cost: CostUsage?
        let dailyTotals: [Date: Int]
        let summary: CursorUsageSummary?
    }

    private func fetchOnlineUsage() async -> OnlineFetch {
        guard let token = await parser.readAccessToken(stateDatabaseURL: stateDatabaseURL),
              let cookie = CursorSession.cookie(jwt: token) else {
            return .missingSession
        }

        do {
            // Tokens (fatal on failure) and the quota summary (best-effort) run together.
            async let csvResult = usageClient.fetchUsageEventsCSV(cookie: cookie)
            async let summaryData = fetchSummarySafely(cookie: cookie)

            let events = CursorUsageCSV.parseEvents(try await csvResult)
            let summary = (await summaryData).flatMap(CursorUsageSummary.decode)

            var windows = UsageWindows(
                calendar: calendar,
                referenceDate: now(),
                emptyConfidence: .providerReported
            )
            var totalCost = 0.0
            for event in events {
                windows.accumulate(
                    TokenUsage(
                        inputTokens: event.inputTokens,
                        outputTokens: event.outputTokens,
                        cacheReadTokens: event.cacheReadTokens,
                        cacheCreationTokens: event.cacheWriteTokens,
                        reasoningTokens: 0,
                        confidence: .providerReported
                    ),
                    timestamp: event.date,
                    dailyTotal: event.totalTokens
                )
                totalCost += event.cost
            }
            let windowed = windows.snapshot()

            return .success(OnlineUsage(
                today: windowed.today,
                week: windowed.week,
                month: windowed.month,
                // Cursor's CSV `Cost` is the amount actually billed; on included-usage
                // plans that is $0, so surface a cost only when there's real spend.
                // API-equivalent value (what these tokens would cost at API rates) is
                // the value engine's job, not this billed figure.
                cost: totalCost > 0 ? CostUsage(
                    amount: totalCost, currency: "USD", confidence: .providerReported
                ) : nil,
                dailyTotals: windowed.dailyTotals,
                summary: summary
            ))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// The quota summary is enrichment, not the headline — a failure here must not
    /// discard the token usage we did fetch, so it never throws.
    private func fetchSummarySafely(cookie: String) async -> Data? {
        try? await usageClient.fetchUsageSummary(cookie: cookie)
    }
}
