#if DEBUG
import Foundation
import AIUsageDashboardCore

/// Debug builds only: `-TokeiProofFixture demo` feeds every screen one fixed, fictional data
/// set, so a capture is safe to publish. Nothing here comes from this Mac: no account names,
/// e-mail addresses, paths or plan prices. The app does not read logs, the saved store, the
/// quota series or the burn history while it is on, and writes none of them.
///
///     Tokei -TokeiProofFixture demo -TokeiProofRoute overview.quota
///
/// Every value is relative to launch time, so countdowns and "today" read the same on any day.
/// `DemoFixtureTests` checks the whole set for a home-directory path or an `@`.
enum DemoFixture {
    static let launchValue = "demo"

    static var isActive: Bool {
        UserDefaults.standard.string(forKey: "TokeiProofFixture") == launchValue
    }

    /// Settings the screens read from `UserDefaults`, fixed for the demo: plan prices, every
    /// agent shown, live quota on. Merged into the argument domain, which is never saved, so
    /// the real preferences are neither read for these keys nor changed.
    static let defaults: [String: Any] = {
        var values: [String: Any] = [
            "maxxer.planCost.claude_code": 100.0,
            "maxxer.planCost.codex": 20.0,
            "maxxer.planCost.cursor": 20.0,
            "claudeNetworkUsageEnabled": true,
            "codexLiveQuotaEnabled": true,
            "cursorNetworkUsageEnabled": true,
            "antigravityOnlineQuotaEnabled": false,
            "geminiNetworkUsageEnabled": true
        ]
        for id in ProviderID.allCases {
            // Only the four demo agents: an unused agent adds an empty row to every screen.
            values["provider_hidden_\(id.rawValue)"] = !ProviderOrder.demo.contains(id)
            if !planCostProviders.contains(id) { values["maxxer.planCost.\(id.rawValue)"] = 0.0 }
        }
        return values
    }()

    private static let planCostProviders: Set<ProviderID> = [.claudeCode, .codex, .cursor]

    /// Puts `defaults` in front of the saved preferences for this run only.
    static func installDefaults(into store: UserDefaults = .standard) {
        var arguments = store.volatileDomain(forName: UserDefaults.argumentDomain)
        for (key, value) in defaults where arguments[key] == nil { arguments[key] = value }
        store.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// Where each agent's tightest window stood one period ago, for the popover's pace notch.
    /// Keyed like `MenuBarView.paceBaselines` (`<provider>_<window>`).
    static let paceBaselines: [String: Double] = [
        "claude_code_five_hour": 71,
        "codex_weekly": 28,
        "cursor_monthly": 64
    ]

    // MARK: Sync

    /// A view model whose every source is the demo: its sync engine's providers return
    /// `snapshots(now:)`, and its store, quota series, burn state and agent snapshot live in a
    /// folder under the temporary directory. Any refresh (launch, Sync now, a retry) therefore
    /// shows the demo again; nothing reads the real logs and nothing writes the real files.
    @MainActor
    static func viewModel() -> DashboardViewModel {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokei-demo-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let series = QuotaSeriesStore(directory: folder)
        let providers: [any UsageProvider] = ProviderOrder.demo.map { DemoProvider(id: $0) }
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: providers), store: UsageStore(directory: folder),
            quotaSeriesStore: series, agentSnapshotWriter: AgentSnapshotWriter(directory: folder),
            watcher: FileWatcher(paths: [folder], pathsProvider: { [folder] }),
            evaluateThresholds: { _ in }
        )
        return DashboardViewModel(
            syncEngine: engine, store: UsageStore(directory: folder),
            burnStateStore: BurnStateStore(directory: folder), quotaSeriesStore: series,
            notifyBurn: { _, _ in }
        )
    }

    private enum ProviderOrder {
        static let demo: [ProviderID] = [.claudeCode, .codex, .cursor, .gemini]
    }

    /// One demo agent, fresh at every fetch so countdowns and "today" stay right.
    private struct DemoProvider: UsageProvider {
        let id: ProviderID
        var displayName: String { id.rawValue }
        var capabilities: ProviderCapabilities { [.localLog, .quota, .tokenUsage] }
        func detectAvailability() async -> ProviderAvailability { .installed }
        func authenticate() async throws -> AuthStatus { .authenticated }
        func fetchSnapshot() async throws -> ProviderSnapshot {
            guard let snapshot = DemoFixture.snapshots(now: Date()).first(where: { $0.providerID == id }) else {
                throw CocoaError(.featureUnsupported)
            }
            return snapshot
        }
    }

    // MARK: Snapshots

    /// Four agents on flat-rate plans with live quota. Codex's five-hour window resets soon
    /// with most of it unused, so routing sends work there first; Claude Code is on pace;
    /// Gemini's day is a little ahead; Cursor's month is nearly spent, so it is the one to avoid.
    static func snapshots(now: Date, calendar: Calendar = .current) -> [ProviderSnapshot] {
        let observed = now.addingTimeInterval(-40)
        let claude = provider(
            .claudeCode, "Claude Code", now: now, calendar: calendar, dailyScale: 21_000_000, seed: 3,
            models: [("claude-opus-4-6", 0.62), ("claude-sonnet-4-6", 0.33), ("claude-haiku-4-5", 0.05)],
            windows: [
                window(.claudeCode, .fiveHour, used: 58, resetIn: 2 * 3_600 + 10 * 60, duration: 5 * 3_600,
                       observed: observed, now: now, bucket: "five_hour", label: "Session"),
                window(.claudeCode, .weekly, used: 44, resetIn: 3 * 86_400 + 6 * 3_600, duration: 7 * 86_400,
                       observed: observed, now: now, bucket: "seven_day", label: "Weekly"),
                window(.claudeCode, .perModel, used: 39, resetIn: 3 * 86_400 + 6 * 3_600, duration: 7 * 86_400,
                       observed: observed, now: now, bucket: "seven_day_opus", label: "Opus")
            ],
            warnings: [ProviderWarning(message: "Plan: Max 5x", level: .info)]
        )
        let codex = provider(
            .codex, "Codex", now: now, calendar: calendar, dailyScale: 9_000_000, seed: 7,
            models: [("gpt-5.2-codex", 0.82), ("gpt-5.1-codex-mini", 0.18)],
            windows: [
                window(.codex, .fiveHour, used: 23, resetIn: 41 * 60, duration: 5 * 3_600,
                       observed: observed, now: now, bucket: "codex_primary"),
                window(.codex, .weekly, used: 36, resetIn: 4 * 86_400 + 2 * 3_600, duration: 7 * 86_400,
                       observed: observed, now: now, bucket: "codex_secondary")
            ],
            warnings: [ProviderWarning(message: "Plan: Plus", level: .info)]
        )
        let cursor = provider(
            .cursor, "Cursor", now: now, calendar: calendar, dailyScale: 2_400_000, seed: 11,
            models: [("claude-sonnet-4-5", 0.7), ("gpt-5.1", 0.3)],
            windows: [
                window(.cursor, .monthly, used: 88, resetIn: 9 * 86_400, duration: 30 * 86_400,
                       observed: observed, now: now, bucket: "cursor_auto", label: "Auto")
            ],
            warnings: [ProviderWarning(message: "Plan: Pro", level: .info)]
        )
        let gemini = provider(
            .gemini, "Gemini", now: now, calendar: calendar, dailyScale: 1_100_000, seed: 5,
            models: [("gemini-3.5-flash", 1)],
            windows: [
                window(.gemini, .daily, used: 47, resetIn: 14 * 3_600, duration: 86_400,
                       observed: observed, now: now, bucket: "gemini_daily")
            ],
            warnings: []
        )
        return routeVariant([claude, codex, cursor, gemini], now: now)
    }

    /// `-TokeiDemoRoute exhausted|stale|one|none`: the same agents with readings that put
    /// "Send work here next" in each of its other states, for proof captures.
    private static func routeVariant(_ snapshots: [ProviderSnapshot], now: Date) -> [ProviderSnapshot] {
        guard let variant = UserDefaults.standard.string(forKey: "TokeiDemoRoute") else { return snapshots }
        return snapshots.map { snapshot in
            let windows: [QuotaWindow] = snapshot.quotaWindows.compactMap { window in
                switch variant {
                case "exhausted":
                    let used = max(window.used ?? 0, 91 + Double(snapshot.providerID.rawValue.count % 7))
                    return QuotaWindow(providerID: window.providerID, type: window.type, used: used, limit: 100,
                                       remaining: 100 - used, resetAt: window.resetAt, confidence: window.confidence,
                                       source: window.source, label: window.label, bucketKey: window.bucketKey,
                                       observedAt: window.observedAt, windowDuration: window.windowDuration)
                case "stale": return window.withObservedAt(now.addingTimeInterval(-2 * 3_600))
                case "one": return snapshot.providerID == .claudeCode ? window : nil
                case "none": return nil
                default: return window
                }
            }
            return ProviderSnapshot(
                providerID: snapshot.providerID, displayName: snapshot.displayName, authStatus: snapshot.authStatus,
                quotaWindows: windows, todayUsage: snapshot.todayUsage, weekUsage: snapshot.weekUsage,
                monthUsage: snapshot.monthUsage, lifetimeUsage: snapshot.lifetimeUsage, costUsage: snapshot.costUsage,
                warnings: snapshot.warnings, lastSyncedAt: snapshot.lastSyncedAt, dailyTotals: snapshot.dailyTotals,
                hourlyTotals: snapshot.hourlyTotals, dailyModelUsage: snapshot.dailyModelUsage
            )
        }
    }

    private static func window(
        _ id: ProviderID, _ type: QuotaWindowType, used: Double, resetIn: TimeInterval, duration: TimeInterval,
        observed: Date, now: Date, bucket: String, label: String? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: id, type: type, used: used, limit: 100, remaining: 100 - used,
            resetAt: now.addingTimeInterval(resetIn), confidence: .providerReported, source: "demo fixture",
            label: label, bucketKey: bucket, observedAt: observed, windowDuration: duration
        )
    }

    /// A believable day of work: quieter at weekends, busier mid-week, never two days alike.
    /// The quiet days sit three and four days back, not on real weekends, so today always
    /// reads as a working day.
    private static func dayWeight(_ offset: Int, seed: Int) -> Double {
        let wave = 0.72 + 0.28 * sin(Double(offset * 3 + seed) * 0.9)
        let jitter = 0.85 + 0.3 * abs(sin(Double(offset * 7 + seed * 13) * 1.7))
        let weekend = offset % 7 == 3 || offset % 7 == 4 ? 0.35 : 1.0
        return wave * jitter * weekend
    }

    private static func provider(
        _ id: ProviderID, _ name: String, now: Date, calendar: Calendar, dailyScale: Double, seed: Int,
        models: [(String, Double)], windows: [QuotaWindow], warnings: [ProviderWarning]
    ) -> ProviderSnapshot {
        let today = calendar.startOfDay(for: now)
        // Today reads as a working day in progress whatever the hour of the capture.
        let dayFraction = 0.62
        var daily: [Date: Int] = [:]
        var hourly: [Date: Int] = [:]
        var byModel: [Date: [String: TokenUsage]] = [:]
        for offset in 0..<120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // History starts 90 days back for every agent but Gemini, added a month ago.
            if offset >= (id == .gemini ? 34 : 96) { continue }
            var total = dailyScale * dayWeight(offset, seed: seed)
            if offset == 0 { total *= dayFraction }
            var dayModels: [String: TokenUsage] = [:]
            var dayTotal = 0
            for (model, share) in models {
                let tokens = total * share
                let usage = TokenUsage(
                    inputTokens: Int(tokens * 0.04), outputTokens: Int(tokens * 0.03),
                    cacheReadTokens: Int(tokens * 0.86), cacheCreationTokens: Int(tokens * 0.07),
                    confidence: .exact
                )
                dayModels[model] = usage
                dayTotal += usage.totalTokens ?? 0
            }
            byModel[day] = dayModels
            daily[day] = dayTotal
            // Working hours carry the day; the heatmap shows a real rhythm.
            let hours = offset == 0 ? Int(now.timeIntervalSince(today) / 3_600) + 1 : 24
            let curve = (0..<24).map { hour -> Double in
                let work = exp(-pow(Double(hour) - 14.5, 2) / 18)
                return hour < 8 ? 0.02 : work + 0.05 * abs(sin(Double(hour * seed + offset)))
            }
            let curveTotal = curve.prefix(hours).reduce(0, +)
            for hour in 0..<min(24, hours) {
                guard curveTotal > 0, let start = calendar.date(byAdding: .hour, value: hour, to: day) else { continue }
                let value = Int(Double(dayTotal) * curve[hour] / curveTotal)
                if value > 0 { hourly[start] = value }
            }
        }
        func sum(_ days: Int) -> TokenUsage {
            byModel.filter { $0.key > (calendar.date(byAdding: .day, value: -days, to: today) ?? today) }
                .values.flatMap(\.values).reduce(TokenUsage(confidence: .exact)) { $0.merging($1) }
        }
        let todayUsage = byModel[today].map { $0.values.reduce(TokenUsage(confidence: .exact)) { $0.merging($1) } }
            ?? .unavailable
        return ProviderSnapshot(
            providerID: id, displayName: name, authStatus: .authenticated, quotaWindows: windows,
            todayUsage: todayUsage, weekUsage: sum(7), monthUsage: sum(30), lifetimeUsage: sum(120),
            costUsage: nil, warnings: warnings, lastSyncedAt: now, dailyTotals: daily, hourlyTotals: hourly,
            dailyModelUsage: byModel
        )
    }
}
#endif
