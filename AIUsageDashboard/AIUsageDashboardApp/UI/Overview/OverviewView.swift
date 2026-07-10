import SwiftUI
import AIUsageDashboardCore

/// The consolidated Overview home (redesign mockup 4): TODAY hero with metric
/// tiles, token-usage-over-time line, usage-by-provider donut, streak/pattern
/// stats, the daily-activity heatmap, and one glanceable per-provider quota
/// row each — rows remain jump-off points into the detail tab.
///
/// All analytics come from the frozen `DashboardViewModel` §4 surface
/// (`overviewTrend/providerSplit/overviewDelta/streak/bestDay/leastActiveDay/
/// dailyAverage/heatmap(for:)`, ranged by `viewModel.range`). Every widget
/// renders an honest empty state when its source is absent.
struct OverviewView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Open a provider's detail tab (wired by `DashboardView` to set nav state).
    var onOpen: (ProviderID) -> Void = { _ in }
    /// Route to the Connections screen for a provider with no live quota.
    var onConnect: () -> Void = {}
    /// Open the `+` add-agent sheet (blank-canvas primary action + header button).
    var onAddAgent: () -> Void = {}

    /// The ranges the segmented selector offers (drives `viewModel.range`).
    private static let rangeOptions: [(range: UsageRange, label: String)] = [
        (.sevenDay, "7D"),
        (.thirtyDay, "30D"),
        (.ninetyDay, "90D"),
    ]

    // MARK: Snapshot-derived display state

    /// One display model per visible provider: identity + its tightest window.
    private struct Entry: Identifiable {
        let providerID: ProviderID
        let displayName: String
        let plan: String?
        let tightest: Utilization?
        var id: ProviderID { providerID }
        /// Sort key: tighter windows first; no-quota rows sink to the bottom.
        var rank: Double { tightest?.usedPercent ?? -1 }
    }

    /// Visible providers, each reduced to its tightest window, sorted by that
    /// window's used percent descending (unavailable providers last).
    private var entries: [Entry] {
        ProviderID.allCases
            .filter { !ProviderVisibility.isHidden($0) }
            .map { id in
                let tightest = viewModel.utilization
                    .filter { $0.providerID == id }
                    .max(by: { $0.usedPercent < $1.usedPercent })
                return Entry(
                    providerID: id,
                    displayName: viewModel.snapshot(for: id)?.displayName ?? fallbackName(id),
                    plan: tightest?.plan,
                    tightest: tightest
                )
            }
            .sorted { $0.rank > $1.rank }
    }

    private func fallbackName(_ id: ProviderID) -> String {
        id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// The provider to nudge new work toward (emptiest plan with real headroom),
    /// or `nil` when routing advice would be noise (#37).
    private var routeTargetID: ProviderID? {
        MaxxerMath.routeTarget(in: viewModel.utilization)?.providerID
    }

    private var aggregateLine: String {
        guard let agg = viewModel.aggregateUtilization else {
            return "— NO LIVE QUOTA CONNECTED"
        }
        // MEAN of per-provider peaks (Core), so label it "AVG".
        return "\(Int(round(agg.usedPercent)))% AVG · \(agg.coveredProviders.count) LIVE"
    }

    /// Today's per-metric usage merged across available providers — straight off
    /// the published snapshots via the existing Core merge.
    private var mergedToday: TokenUsage {
        viewModel.snapshots
            .filter { viewModel.isAvailable($0.providerID) }
            .map(\.todayUsage)
            .reduce(TokenUsage.unavailable) { $0.merging($1) }
    }

    /// Element-wise union of the visible providers' §4 heatmaps: a cell is `nil`
    /// only when NO provider reports it; otherwise the sum of those that do.
    /// `nil` overall when no visible provider has an hourly source yet.
    private var combinedHeatmap: [[Int?]]? {
        let matrices = ProviderID.allCases
            .filter { !ProviderVisibility.isHidden($0) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HairlineDivider()

            if entries.isEmpty {
                blankCanvas
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroCard
                        chartsRow
                        patternsCard
                        heatmapCard
                        providersCard
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Overview")
                Text(aggregateLine)
                    .font(.mono(size: 18))
                    .monospacedDigit()
                    .foregroundColor(viewModel.aggregateUtilization == nil ? PadzyTheme.muted : PadzyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 12)
            rangeSelector
            AddAgentButton { onAddAgent() }
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// Segmented range control bound to `viewModel.range`: hairline-bounded,
    /// accent tick under the active option (accent = active state, not a data hue).
    private var rangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(Self.rangeOptions, id: \.label) { option in
                let isSelected = viewModel.range == option.range
                Button {
                    viewModel.range = option.range
                } label: {
                    Text(option.label)
                        .font(.mono(size: 11))
                        .foregroundColor(isSelected ? PadzyTheme.ink : PadzyTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? PadzyTheme.accent : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Hero

    private var heroCard: some View {
        SectionCard("Today") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mergedToday.totalTokens.map { TokenFormatter.format($0) } ?? "—")
                        .font(.mono(size: 52))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    if let delta = viewModel.overviewDelta {
                        DeltaLabel(delta: delta, caption: AnalyticsFormat.deltaCaption(viewModel.range))
                    }
                }
                Spacer(minLength: 12)
                // Single total-tokens trend (per-metric hero sparklines need a
                // per-day metric split that doesn't exist yet — out of scope).
                AreaTrendChart(values: viewModel.overviewTrend.map(\.tokens))
                    .frame(width: 200, height: 64)
                    .accessibilityHidden(true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                StatCard(kicker: "Input", value: format(mergedToday.inputTokens))
                StatCard(kicker: "Output", value: format(mergedToday.outputTokens))
                StatCard(kicker: "Cache read", value: format(mergedToday.cacheReadTokens))
                StatCard(kicker: "Cache write", value: format(mergedToday.cacheCreationTokens))
            }
        }
    }

    private func format(_ value: Int?) -> String {
        value.map { TokenFormatter.format($0) } ?? "—"
    }

    // MARK: Charts row

    private var chartsRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], alignment: .leading, spacing: 16) {
            SectionCard("Token usage over time", trailing: {
                Text(AnalyticsFormat.rangeTitle(viewModel.range))
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
            }) {
                LineTrendChart(points: viewModel.overviewTrend)
                    .frame(height: 200)
            }

            SectionCard("Usage by provider") {
                ProviderDonut(slices: viewModel.providerSplit)
                    .frame(minHeight: 200)
            }
        }
    }

    // MARK: Patterns

    private var patternsCard: some View {
        SectionCard("Patterns", trailing: {
            Text(AnalyticsFormat.rangeTitle(viewModel.range))
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
        }) {
            let streak = viewModel.streak
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                StatCard(kicker: "Current streak",
                         value: streak.current > 0 ? "\(streak.current) DAYS" : "—")
                StatCard(kicker: "Longest streak",
                         value: streak.longest > 0 ? "\(streak.longest) DAYS" : "—")
                StatCard(kicker: "Best day",
                         value: viewModel.bestDay.map { TokenFormatter.format($0.tokens) } ?? "—",
                         deltaCaption: viewModel.bestDay.map { AnalyticsFormat.shortDay($0.date) })
                StatCard(kicker: "Least active",
                         value: viewModel.leastActiveDay.map { TokenFormatter.format($0.tokens) } ?? "—",
                         deltaCaption: viewModel.leastActiveDay.map { AnalyticsFormat.shortDay($0.date) })
                StatCard(kicker: "Daily average",
                         value: viewModel.dailyAverage.map { TokenFormatter.format($0) } ?? "—")
            }
        }
    }

    // MARK: Heatmap

    private var heatmapCard: some View {
        SectionCard("Daily activity") {
            ActivityHeatmap(matrix: combinedHeatmap ?? [])
                .frame(minHeight: 96)
        }
    }

    // MARK: Providers

    private var providersCard: some View {
        SectionCard("Providers") {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ProviderOverviewRow(
                        providerID: entry.providerID,
                        displayName: entry.displayName,
                        plan: entry.plan,
                        tightest: entry.tightest,
                        isRouteTarget: entry.providerID == routeTargetID,
                        horizontalPadding: 4,
                        onOpen: { onOpen(entry.providerID) },
                        onConnect: onConnect
                    )
                    if index < entries.count - 1 {
                        HairlineDivider()
                    }
                }
            }
        }
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
                         today: TokenUsage(inputTokens: 3_800_000, outputTokens: 700_000, confidence: .localParsed),
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
