import SwiftUI
import AIUsageDashboardCore

/// The consolidated Overview home, rebuilt to the WP-5 mockup: a Usage/Quota metric
/// selector, a big hero number + delta + one-line context, a full-width trend (or
/// per-agent quota bars), the 1px-gap agent grid, the usage-split donut beside the
/// by-weekday bars, and the when-you-work heatmap. Sections are ruled off by
/// hairlines and named with mono kickers — no card stack, no numbered `NN /` labels.
///
/// All analytics come from the frozen `DashboardViewModel` §4 surface
/// (`overviewTrend / providerSplit / overviewDelta / streak / dailyAverage /
/// utilization / heatmap(for:)`, ranged by `viewModel.range`), plus `MaxxerMath`
/// for the merged-today total and the tightest window. Every widget renders an
/// honest empty state when its source is absent, and unknowns read `—`, never `0`.
struct OverviewView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Open a provider's drill-in (wired by `DashboardView` to `openProvider`).
    var onSelectProvider: (ProviderID) -> Void = { _ in }
    /// Open the `+` add-agent sheet (blank-canvas + AGENTS-row primary action).
    var onAddAgent: () -> Void = {}

    /// Usage vs Quota lens — local pane state, animated on change (reduce-motion safe).
    @State private var metric: OverviewMetric = .usage
    /// Measured content width, drives the split row's side-by-side ↔ stacked reflow.
    @State private var contentWidth: CGFloat = 0

    // MARK: Derived display state (data sources preserved from the prior pane)

    /// Every non-hidden provider — one agent cell each, in `ProviderID` order.
    private var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { !ProviderVisibility.isHidden($0) }
    }

    private func fallbackName(_ id: ProviderID) -> String {
        id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func displayName(_ id: ProviderID) -> String {
        viewModel.snapshot(for: id)?.displayName ?? fallbackName(id)
    }

    /// Today's per-metric usage merged across the visible + available providers —
    /// the same Core merge the `01 / OVERVIEW` tab pill uses, so hero and pill can
    /// never disagree. (Preserved verbatim from the prior pane.)
    private var mergedToday: TokenUsage {
        MaxxerMath.mergedTodayUsage(in: ProviderVisibility.visible(viewModel.snapshots).filter {
            viewModel.isAvailable($0.providerID)
        })
    }

    /// Visible providers that actually report token data today — the hero's "N
    /// active agents" (Antigravity/Gemini with no token data are excluded).
    private var activeAgentCount: Int {
        ProviderVisibility.visible(viewModel.snapshots)
            .filter { $0.todayUsage.totalTokens != nil }
            .count
    }

    /// The single tightest live window across providers (the constraint that
    /// actually bites) — the Quota hero and the ambient banner share this.
    private var tightestWindow: Utilization? {
        MaxxerMath.tightestWindow(in: viewModel.utilization)
    }

    /// Each provider reduced to its tightest (highest-used) live window.
    private var tightestByProvider: [ProviderID: Utilization] {
        var result: [ProviderID: Utilization] = [:]
        for util in viewModel.utilization {
            if let existing = result[util.providerID] {
                if util.usedPercent > existing.usedPercent { result[util.providerID] = util }
            } else {
                result[util.providerID] = util
            }
        }
        return result
    }

    /// The single provider with the most quota headroom (lowest max-used% among
    /// providers that have quota) — earns the green "route new work here" dot. Only
    /// when at least two agents have quota, so the hint always implies a choice.
    private var headroomProviderID: ProviderID? {
        let quotaBearing: [(id: ProviderID, pct: Double)] = visibleProviders.compactMap { id in
            tightestByProvider[id].map { (id, $0.usedPercent) }
        }
        guard quotaBearing.count >= 2 else { return nil }
        return quotaBearing.min(by: { $0.pct < $1.pct })?.id
    }

    /// One resolved cell per visible provider for the agent grid.
    private var agentModels: [AgentCellModel] {
        let headroom = headroomProviderID
        return visibleProviders.map { id in
            let today = viewModel.snapshot(for: id)?.todayUsage
            let tightest = tightestByProvider[id]

            let stat: String
            let color: Color
            var estimated = false
            if let today, let total = today.totalTokens {
                stat = TokenFormatter.format(total)
                color = PadzyTheme.ink
                estimated = today.confidence == .estimated
            } else if let tightest {
                stat = "\(Int(round(tightest.usedPercent)))%"
                color = PadzyTheme.ink2
            } else {
                stat = "—"
                color = PadzyTheme.ink5
            }

            return AgentCellModel(
                providerID: id,
                name: displayName(id),
                stat: stat,
                statColor: color,
                isEstimated: estimated,
                hasHeadroom: id == headroom
            )
        }
    }

    /// Per-agent quota bars for the Quota metric — tightest window per provider,
    /// sorted fullest-first.
    private var quotaBars: [(id: ProviderID, name: String, pct: Double)] {
        visibleProviders
            .compactMap { id -> (id: ProviderID, name: String, pct: Double)? in
                guard let util = tightestByProvider[id] else { return nil }
                return (id, displayName(id), util.usedPercent)
            }
            .sorted { $0.pct > $1.pct }
    }

    /// Average tokens per weekday (Mon→Sun), bucketing the ranged trend by
    /// `Calendar.component(.weekday)`.
    private var weekdayBars: [(label: String, value: Int)] {
        let order = [2, 3, 4, 5, 6, 7, 1] // Calendar weekday (1=Sun); Monday-first display.
        let labels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        var sums: [Int: Int] = [:]
        var counts: [Int: Int] = [:]
        let calendar = Calendar.current
        for point in viewModel.overviewTrend {
            let weekday = calendar.component(.weekday, from: point.date)
            sums[weekday, default: 0] += point.tokens
            counts[weekday, default: 0] += 1
        }
        return zip(order, labels).map { weekday, label in
            let count = counts[weekday] ?? 0
            let avg = count > 0 ? (sums[weekday] ?? 0) / count : 0
            return (label, avg)
        }
    }

    /// Element-wise union of the visible providers' §4 heatmaps: a cell is `nil`
    /// only when NO provider reports it; otherwise the sum of those that do.
    /// (Preserved verbatim from the prior pane.)
    private var combinedHeatmap: [[Int?]]? {
        let matrices = visibleProviders
            .compactMap { viewModel.heatmap(for: $0) }
            .filter { $0.count == 7 }
        guard !matrices.isEmpty else { return nil }
        return (0..<7).map { row in
            (0..<24).map { column -> Int? in
                let cells = matrices.compactMap { matrix -> Int? in
                    guard matrix[row].indices.contains(column) else { return nil }
                    return matrix[row][column]
                }
                return cells.isEmpty ? nil : cells.reduce(0, +)
            }
        }
    }

    // MARK: Body

    var body: some View {
        Group {
            if let error = viewModel.errorMessage {
                SurfaceStateView(
                    header: "Overview",
                    kind: .error(headline: "Sync failed", detail: error),
                    onRetry: { Task { await viewModel.refresh() } }
                )
            } else if visibleProviders.isEmpty {
                blankCanvas
            } else if viewModel.isLoading && viewModel.snapshots.isEmpty {
                SurfaceStateView(header: "Overview", kind: .loading(message: "Reading local logs"))
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PadzySpace.xl) {
                OverviewMetricSelector(metric: $metric)

                VStack(alignment: .leading, spacing: PadzySpace.l) {
                    hero
                    mainChart
                }
                .animation(reduceMotion ? nil : PadzyMotion.settle, value: metric)

                agentsSection
                splitAndWeekdaySection
                heatmapSection
            }
            .padding(PadzySpace.xl)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: OverviewContentWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(OverviewContentWidthKey.self) { contentWidth = $0 }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: PadzySpace.s) {
            Text(heroNumber)
                .font(.mono(size: 62, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .lineSpacing(0)
                .minimumScaleFactor(0.4)
                .accessibilityLabel("\(metric.title), \(heroNumber)")

            if metric == .usage, let delta = viewModel.overviewDelta {
                deltaLine(delta)
            }

            Text(heroSubtitle)
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroNumber: String {
        switch metric {
        case .usage: return mergedToday.totalTokens.map { TokenFormatter.format($0) } ?? "—"
        case .quota: return tightestWindow.map { "\(Int(round($0.usedPercent)))%" } ?? "—"
        }
    }

    private var heroSubtitle: String {
        switch metric {
        case .usage:
            let count = activeAgentCount
            return "tokens today across \(count) active agent\(count == 1 ? "" : "s")"
        case .quota:
            guard let tightest = tightestWindow else { return "No live quota connected yet." }
            return "\(displayName(tightest.providerID)) is your tightest window right now."
        }
    }

    private func deltaLine(_ delta: Double) -> some View {
        HStack(spacing: 6) {
            Text("\(delta >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(delta)))%")
                .font(.mono(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink3)
            Text(AnalyticsFormat.deltaCaption(viewModel.range))
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(delta >= 0 ? "up" : "down") \(String(format: "%.1f", abs(delta))) percent \(AnalyticsFormat.deltaCaption(viewModel.range))")
    }

    // MARK: Main chart / quota bars

    @ViewBuilder
    private var mainChart: some View {
        if metric == .usage {
            LineTrendChart(points: viewModel.overviewTrend)
                .frame(height: 200)
                .transition(.opacity)
        } else {
            AgentQuotaBars(bars: quotaBars)
                .transition(.opacity)
        }
    }

    // MARK: Agents

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            HairlineDivider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                kicker("Agents · \(visibleProviders.count)")
                Spacer(minLength: 8)
                Button(action: onAddAgent) {
                    Text("+ Add agent")
                        .font(.sans(size: 12))
                        .foregroundColor(PadzyTheme.ink4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add agent")
            }
            AgentGrid(models: agentModels, onSelect: onSelectProvider)
        }
    }

    // MARK: Usage split + by weekday

    private var splitAndWeekdaySection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.l) {
            HairlineDivider()
            if contentWidth > 0 && contentWidth < 620 {
                VStack(alignment: .leading, spacing: PadzySpace.xl) {
                    usageSplitColumn
                    weekdayColumn
                }
            } else {
                HStack(alignment: .top, spacing: PadzySpace.xxl) {
                    usageSplitColumn
                    weekdayColumn
                }
            }
        }
    }

    private var usageSplitColumn: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            kicker("Usage split · \(AnalyticsFormat.rangeTitle(viewModel.range))")
            ProviderDonut(slices: viewModel.providerSplit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekdayColumn: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            kicker("By weekday")
            WeekdayBars(bars: weekdayBars)
            HStack(alignment: .top, spacing: PadzySpace.xxl) {
                miniStat(
                    "Daily average",
                    value: viewModel.dailyAverage.map { TokenFormatter.format($0) } ?? "—"
                )
                let streak = viewModel.streak
                miniStat(
                    "Active streak",
                    value: streak.current > 0 ? "\(streak.current)d" : "—",
                    caption: streak.longest > 0 ? "best \(streak.longest)d" : nil
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: When you work

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            HairlineDivider()
            kicker("When you work")
            ActivityHeatmap(matrix: combinedHeatmap ?? [])
                .frame(minHeight: 96)
        }
    }

    // MARK: Small parts

    private func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.mono(size: 10))
            .tracking(10 * 0.16)
            .foregroundColor(PadzyTheme.ink5)
            .lineLimit(1)
    }

    private func miniStat(_ title: String, value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.mono(size: 9))
                .tracking(9 * 0.16)
                .foregroundColor(PadzyTheme.ink5)
            Text(value)
                .font(.mono(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
            if let caption {
                Text(caption.uppercased())
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.ink5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Blank canvas

    /// Blank-canvas first-run state: no providers on the canvas yet. Leads with the
    /// `+` — the primary action — instead of a wall of empty provider rows.
    private var blankCanvas: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NO AGENTS LINKED YET")
                .font(.display(size: 18, weight: .black))
                .foregroundColor(PadzyTheme.ink)
            Text("Tokei tracks local AI-coding usage. Link a coding agent to start — detection reads only paths on your disk, nothing leaves your Mac.")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            AddAgentButton { onAddAgent() }
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Measures the content column width for the split-row reflow (separate from the
/// agent grid's own width key so the two readers never race).
struct OverviewContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

@MainActor
private func mockViewModel(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    return vm
}

private func previewDailyTotals(days: Int) -> [Date: Int] {
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000]
    let today = Calendar.current.startOfDay(for: Date())
    var totals: [Date: Int] = [:]
    for i in 0..<days {
        if let day = Calendar.current.date(byAdding: .day, value: -i, to: today) {
            totals[day] = values[i % values.count]
        }
    }
    return totals
}

private func previewHourlyTotals() -> [Date: Int] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    var totals: [Date: Int] = [:]
    for daysBack in 0..<7 {
        for hour in [9, 11, 14, 16, 21] {
            if let day = calendar.date(byAdding: .day, value: -daysBack, to: today),
               let slot = calendar.date(byAdding: .hour, value: hour, to: day) {
                totals[slot] = (daysBack + 1) * (hour % 5 + 1) * 120_000
            }
        }
    }
    return totals
}

@MainActor
private func mockSnapshot(
    _ id: ProviderID,
    name: String,
    plan: String? = nil,
    windows: [QuotaWindow] = [],
    today: TokenUsage = .unavailable,
    dailyTotals: [Date: Int]? = nil,
    hourlyTotals: [Date: Int]? = nil
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: windows,
        todayUsage: today,
        weekUsage: .unavailable,
        warnings: plan.map { [ProviderWarning(message: "Plan: \($0)", level: .info)] } ?? [],
        dailyTotals: dailyTotals,
        hourlyTotals: hourlyTotals
    )
}

@MainActor
private func window(_ id: ProviderID, _ type: QuotaWindowType, used: Double, inHours: Double) -> QuotaWindow {
    QuotaWindow(
        providerID: id, type: type, used: used, limit: 100,
        resetAt: Date().addingTimeInterval(inHours * 3600),
        confidence: .providerReported, source: "preview"
    )
}

#Preview("Full · live + tokens + hourly") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 95, inHours: 105),
                                   window(.claudeCode, .session, used: 40, inHours: 3)],
                         today: TokenUsage(inputTokens: 12_400_000, outputTokens: 1_900_000,
                                           cacheReadTokens: 48_100_000, cacheCreationTokens: 3_200_000,
                                           confidence: .exact),
                         dailyTotals: previewDailyTotals(days: 14),
                         hourlyTotals: previewHourlyTotals()),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro",
                         windows: [window(.cursor, .monthly, used: 78, inHours: 11)]),
            mockSnapshot(.antigravity, name: "Antigravity",
                         windows: [window(.antigravity, .fiveHour, used: 32, inHours: 3)]),
            mockSnapshot(.codex, name: "Codex",
                         windows: [window(.codex, .weekly, used: 12, inHours: 60)],
                         today: TokenUsage(inputTokens: 3_800_000, outputTokens: 700_000, confidence: .estimated),
                         dailyTotals: previewDailyTotals(days: 7)),
        ]))
        .frame(width: 980, height: 1250)
        .background(PadzyTheme.ground)
}

#Preview("Narrow 640 · no hourly") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 88, inHours: 105)],
                         today: TokenUsage(inputTokens: 5_100_000, outputTokens: 900_000, confidence: .exact),
                         dailyTotals: previewDailyTotals(days: 7)),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro"),
        ]))
        .frame(width: 640, height: 1150)
        .background(PadzyTheme.ground)
}

#Preview("Blank canvas") {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(true, for: id) }
    return OverviewView(onAddAgent: {})
        .environmentObject(mockViewModel([]))
        .frame(width: 720, height: 520)
        .background(PadzyTheme.ground)
}

#Preview("All unavailable · empty analytics") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code"),
            mockSnapshot(.cursor, name: "Cursor"),
            mockSnapshot(.antigravity, name: "Antigravity"),
        ]))
        .frame(width: 760, height: 1000)
        .background(PadzyTheme.ground)
}
