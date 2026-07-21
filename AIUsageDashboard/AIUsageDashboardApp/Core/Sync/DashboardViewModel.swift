import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var snapshots: [ProviderSnapshot] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastSyncedAt: Date?
    /// Selecting any provider always exits the Settings pane (they are one right-pane
    /// selection), so the invariant lives here rather than at every call site.
    @Published public var selectedProvider: ProviderID = .claudeCode {
        didSet { showingSettings = false }
    }
    /// When true the dashboard's right pane shows the in-app Settings surface instead
    /// of the selected provider's usage. Shared so the menu-bar entry can drive it too.
    @Published public var showingSettings = false
    @Published public var range: UsageRange = .sevenDay

    private let syncEngine: SyncEngine
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var updatesTask: Task<Void, Never>?

    public init(
        syncEngine: SyncEngine = .shared,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.syncEngine = syncEngine
        self.calendar = calendar
        self.now = now
    }

    deinit {
        updatesTask?.cancel()
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        snapshots = await syncEngine.refreshAll()
        lastSyncedAt = Date()
        isLoading = false
    }

    /// Starts the file watcher and subscribes to sync results so auto-refreshes
    /// (and refreshes triggered elsewhere) update this view model. Idempotent.
    public func beginAutoSync() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [syncEngine, weak self] in
            let stream = syncEngine.updates
            await syncEngine.startAutoSync()
            for await snapshots in stream {
                guard let self else { return }
                await MainActor.run {
                    self.snapshots = snapshots
                    self.lastSyncedAt = Date()
                }
            }
        }
    }

    public var claudeSnapshot: ProviderSnapshot? {
        snapshots.first { $0.providerID == .claudeCode }
    }

    public func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        snapshots.first { $0.providerID == providerID }
    }

    public func isAvailable(_ providerID: ProviderID) -> Bool {
        guard let snapshot = snapshot(for: providerID) else { return false }
        if providerID == .claudeCode {
            return true
        }
        let nonUnavailableQuotaWindows = snapshot.quotaWindows.filter { $0.confidence != .unavailable }
        let hasTokens = snapshot.todayUsage.totalTokens != nil && snapshot.todayUsage.confidence != .unavailable && snapshot.todayUsage.totalTokens! > 0
        let hasCost = snapshot.costUsage?.amount != nil && snapshot.costUsage?.confidence != .unavailable
        // A provider is also "available" when it exposes a plan/tier signal (a `"Plan:"`
        // info warning) or local daily-activity totals, even with no token/quota/cost data —
        // e.g. Cursor offline (plan + accepted-lines). Without this, plan-only providers
        // render as UNAVAILABLE despite being connected.
        let hasPlanSignal = snapshot.warnings.contains {
            $0.level == .info && $0.message.range(of: "Plan:", options: [.caseInsensitive]) != nil
        }
        let hasDailyTotals = !(snapshot.dailyTotals?.isEmpty ?? true)
        return hasTokens || !nonUnavailableQuotaWindows.isEmpty || hasCost || hasPlanSignal || hasDailyTotals
    }

    public func selectNextProvider() {
        let available = ProviderID.allCases.filter { isAvailable($0) }
        guard !available.isEmpty else { return }
        if let currentIndex = available.firstIndex(of: selectedProvider) {
            let nextIndex = (currentIndex + 1) % available.count
            selectedProvider = available[nextIndex]
        } else {
            selectedProvider = available.first ?? .claudeCode
        }
    }

    public func selectPreviousProvider() {
        let available = ProviderID.allCases.filter { isAvailable($0) }
        guard !available.isEmpty else { return }
        if let currentIndex = available.firstIndex(of: selectedProvider) {
            let prevIndex = (currentIndex - 1 + available.count) % available.count
            selectedProvider = available[prevIndex]
        } else {
            selectedProvider = available.first ?? .claudeCode
        }
    }

    public var menuBarTodayTotal: Int {
        snapshots.compactMap { isAvailable($0.providerID) ? $0.todayUsage.totalTokens : nil }.reduce(0, +)
    }

    // MARK: - Utilization spine (additive, read-only — derived from `snapshots`)

    /// The unified live-quota % across providers, mapped from the current snapshots.
    /// Purely derived; does not change any published state.
    public var utilization: [Utilization] {
        UtilizationEngine.utilizations(from: snapshots)
    }

    /// The single "today's utilization across plans" aggregate, with the context
    /// (covered providers, coverage flag) needed to explain it. `nil` when no
    /// provider reports usable quota.
    public var aggregateUtilization: AggregateUtilization? {
        UtilizationEngine.aggregate(from: snapshots)
    }

    /// Convenience: just the aggregate percentage, `nil` when no coverage.
    /// "Today" is the product framing (the denominator of "am I maxxing today"),
    /// not a daily window — the underlying value is a horizon-agnostic peak across
    /// each provider's windows (see `AggregateUtilization`). The Maxxer Score (#23)
    /// owns whether to weight or split by horizon.
    public var aggregateUtilizationToday: Double? {
        aggregateUtilization?.usedPercent
    }

    // MARK: - Visual redesign analytics surface

    public var overviewTrend: [(date: Date, tokens: Int)] {
        UsageAnalytics.trend(
            dailyTotals: overviewDailyTotals,
            range: range,
            calendar: calendar,
            now: now()
        )
    }

    public var providerSplit: [(provider: ProviderID, tokens: Int)] {
        UsageAnalytics.providerSplit(
            snapshots: snapshots,
            range: range,
            calendar: calendar,
            now: now(),
            hiddenProviders: hiddenProviders
        )
    }

    public var overviewDelta: Double? {
        let dailyTotals = overviewDailyTotals
        let current = UsageAnalytics.total(dailyTotals: dailyTotals, range: range, calendar: calendar, now: now())
        let previous = UsageAnalytics.previousTotal(
            dailyTotals: dailyTotals,
            range: range,
            calendar: calendar,
            now: now()
        )
        return UsageAnalytics.delta(current: current, previous: previous)
    }

    public var streak: (current: Int, longest: Int) {
        UsageAnalytics.streak(dailyTotals: rangedOverviewDailyTotals, calendar: calendar, now: now())
    }

    public var bestDay: (date: Date, tokens: Int)? {
        UsageAnalytics.bestDay(dailyTotals: rangedOverviewDailyTotals)
    }

    public var leastActiveDay: (date: Date, tokens: Int)? {
        UsageAnalytics.leastActiveDay(dailyTotals: rangedOverviewDailyTotals)
    }

    public var dailyAverage: Int? {
        UsageAnalytics.dailyAverage(dailyTotals: rangedOverviewDailyTotals)
    }

    public func trend(for id: ProviderID) -> [(date: Date, tokens: Int)] {
        guard let dailyTotals = snapshot(for: id)?.dailyTotals else { return [] }
        return UsageAnalytics.trend(dailyTotals: dailyTotals, range: range, calendar: calendar, now: now())
    }

    public func thisWeek(
        for id: ProviderID
    ) -> (peakDayWeekday: Int, peakDayTokens: Int, dailyAverage: Int, delta: Double?)? {
        guard let dailyTotals = snapshot(for: id)?.dailyTotals else { return nil }
        let current = UsageAnalytics.filteredDailyTotals(
            dailyTotals,
            range: .days(7),
            calendar: calendar,
            now: now()
        )
        guard let peak = UsageAnalytics.peakDay(dailyTotals: current, calendar: calendar),
              let average = UsageAnalytics.dailyAverage(dailyTotals: current) else {
            return nil
        }
        let currentTotal = current.values.reduce(0, +)
        let previousTotal = UsageAnalytics.previousTotal(
            dailyTotals: dailyTotals,
            range: .sevenDay,
            calendar: calendar,
            now: now()
        )
        return (
            peakDayWeekday: peak.weekday,
            peakDayTokens: peak.tokens,
            dailyAverage: average,
            delta: UsageAnalytics.delta(current: currentTotal, previous: previousTotal)
        )
    }

    public func heatmap(for id: ProviderID) -> [[Int?]]? {
        guard let hourlyTotals = snapshot(for: id)?.hourlyTotals else { return nil }
        return UsageAnalytics.heatmapMatrix(
            hourlyTotals: hourlyTotals,
            range: range,
            calendar: calendar,
            now: now()
        )
    }

    public func peakHour(for id: ProviderID) -> (hour: Int, tokens: Int)? {
        guard let hourlyTotals = snapshot(for: id)?.hourlyTotals else { return nil }
        return UsageAnalytics.peakHour(hourlyTotals: hourlyTotals, calendar: calendar)
    }

    private var overviewDailyTotals: [Date: Int] {
        UsageAnalytics.aggregateDailyTotals(
            snapshots: snapshots,
            hiddenProviders: hiddenProviders,
            calendar: calendar
        )
    }

    private var rangedOverviewDailyTotals: [Date: Int] {
        UsageAnalytics.filteredDailyTotals(
            overviewDailyTotals,
            range: UsageAnalytics.dailyRange(for: range),
            calendar: calendar,
            now: now()
        )
    }

    private var hiddenProviders: Set<ProviderID> {
        Set(ProviderID.allCases.filter { providerID in
            UserDefaults.standard.bool(forKey: "provider_hidden_\(providerID.rawValue)")
        })
    }
}
