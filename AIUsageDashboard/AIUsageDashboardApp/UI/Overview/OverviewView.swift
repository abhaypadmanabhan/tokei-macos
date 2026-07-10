import SwiftUI
import AIUsageDashboardCore

/// The consolidated Overview home (redesign mockup 4): TODAY hero with metric
/// tiles, token-usage-over-time line, usage-by-provider donut, streak/pattern
/// stats, the daily-activity heatmap (empty until hourly data lands), and one
/// glanceable per-provider quota row each — rows remain jump-off points into
/// the detail tab.
///
/// Wave 1: hero totals/tiles + provider quota rows are REAL (published
/// snapshot state); the analytics widgets render the `SampleChip`-labeled
/// `OverviewAnalyticsFeed.sample()` until WP-1's frozen VM props land (Wave 2).
struct OverviewView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Open a provider's detail tab (wired by `DashboardView` to set nav state).
    var onOpen: (ProviderID) -> Void = { _ in }
    /// Route to the Connections screen for a provider with no live quota.
    var onConnect: () -> Void = {}
    /// Open the `+` add-agent sheet (blank-canvas primary action + header button).
    var onAddAgent: () -> Void = {}

    /// Trailing window the analytics widgets aggregate over. Wave 2 maps this to
    /// `viewModel.range` (Core `UsageRange`); until then it resizes the sample feed.
    enum OverviewRange: String, CaseIterable, Identifiable {
        case sevenDay = "7D"
        case thirtyDay = "30D"
        case ninetyDay = "90D"

        var id: String { rawValue }
        var days: Int {
            switch self {
            case .sevenDay: return 7
            case .thirtyDay: return 30
            case .ninetyDay: return 90
            }
        }
        var title: String {
            switch self {
            case .sevenDay: return "LAST 7 DAYS"
            case .thirtyDay: return "LAST 30 DAYS"
            case .ninetyDay: return "LAST 90 DAYS"
            }
        }
    }

    @State private var range: OverviewRange = .sevenDay

    /// Wave-1 analytics source (see `OverviewAnalyticsFeed` doc).
    private var feed: OverviewAnalyticsFeed { .sample(days: range.days) }

    // MARK: Real snapshot-derived display state

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

    /// Today's per-metric usage merged across available providers — REAL,
    /// straight off the published snapshots via the existing Core merge.
    private var mergedToday: TokenUsage {
        viewModel.snapshots
            .filter { viewModel.isAvailable($0.providerID) }
            .map(\.todayUsage)
            .reduce(TokenUsage.unavailable) { $0.merging($1) }
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

    /// Segmented range control: hairline-bounded, accent tick under the active
    /// option (accent = active state, not a data hue).
    private var rangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(OverviewRange.allCases) { option in
                let isSelected = range == option
                Button {
                    range = option
                } label: {
                    Text(option.rawValue)
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

    // MARK: Hero (real data)

    private var heroCard: some View {
        SectionCard("Today", trailing: {
            if feed.isSample { SampleChip() }
        }) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mergedToday.totalTokens.map { TokenFormatter.format($0) } ?? "—")
                        .font(.mono(size: 52))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    if let delta = feed.delta {
                        DeltaLabel(delta: delta, caption: "vs yesterday")
                    }
                }
                Spacer(minLength: 12)
                // Single total-tokens trend (per-metric hero sparklines are out of
                // scope this round — the per-day metric split doesn't exist yet).
                AreaTrendChart(values: feed.trend.map(\.tokens))
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

    // MARK: Charts row (sample feed until Wave 2)

    private var chartsRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], alignment: .leading, spacing: 16) {
            SectionCard("Token usage over time", trailing: {
                HStack(spacing: 8) {
                    if feed.isSample { SampleChip() }
                    Text(range.title)
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.muted)
                }
            }) {
                LineTrendChart(points: feed.trend)
                    .frame(height: 200)
            }

            SectionCard("Usage by provider", trailing: {
                if feed.isSample { SampleChip() }
            }) {
                ProviderDonut(slices: feed.providerSplit)
                    .frame(minHeight: 200)
            }
        }
    }

    // MARK: Patterns (sample feed until Wave 2)

    private var patternsCard: some View {
        SectionCard("Patterns", trailing: {
            if feed.isSample { SampleChip() }
        }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                StatCard(kicker: "Current streak",
                         value: feed.streak.current > 0 ? "\(feed.streak.current) DAYS" : "—")
                StatCard(kicker: "Longest streak",
                         value: feed.streak.longest > 0 ? "\(feed.streak.longest) DAYS" : "—")
                StatCard(kicker: "Best day",
                         value: feed.bestDay.map { TokenFormatter.format($0.tokens) } ?? "—",
                         deltaCaption: feed.bestDay.map { AnalyticsFormat.shortDay($0.date) })
                StatCard(kicker: "Least active",
                         value: feed.leastActiveDay.map { TokenFormatter.format($0.tokens) } ?? "—",
                         deltaCaption: feed.leastActiveDay.map { AnalyticsFormat.shortDay($0.date) })
                StatCard(kicker: "Daily average",
                         value: feed.dailyAverage.map { TokenFormatter.format($0) } ?? "—")
            }
        }
    }

    // MARK: Heatmap (honest empty until Phase 1b hourly data)

    private var heatmapCard: some View {
        SectionCard("Daily activity") {
            ActivityHeatmap(matrix: feed.heatmap ?? [])
                .frame(minHeight: 96)
        }
    }

    // MARK: Providers (real data)

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

@MainActor
private func mockSnapshot(
    _ id: ProviderID,
    name: String,
    plan: String? = nil,
    windows: [QuotaWindow] = [],
    today: TokenUsage = .unavailable
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: windows,
        todayUsage: today,
        weekUsage: .unavailable,
        warnings: plan.map { [ProviderWarning(message: "Plan: \($0)", level: .info)] } ?? []
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

#Preview("Full · live + tokens") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 95, inHours: 105),
                                   window(.claudeCode, .session, used: 40, inHours: 3)],
                         today: TokenUsage(inputTokens: 12_400_000, outputTokens: 1_900_000,
                                           cacheReadTokens: 48_100_000, cacheCreationTokens: 3_200_000,
                                           confidence: .exact)),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro",
                         windows: [window(.cursor, .monthly, used: 78, inHours: 11)]),
            mockSnapshot(.antigravity, name: "Antigravity",
                         windows: [window(.antigravity, .fiveHour, used: 32, inHours: 3)]),
            mockSnapshot(.codex, name: "Codex",
                         windows: [window(.codex, .weekly, used: 12, inHours: 60)],
                         today: TokenUsage(inputTokens: 3_800_000, outputTokens: 700_000, confidence: .localParsed)),
        ]))
        .frame(width: 980, height: 1200)
        .background(PadzyTheme.ground)
}

#Preview("Narrow 640") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 88, inHours: 105)],
                         today: TokenUsage(inputTokens: 5_100_000, outputTokens: 900_000, confidence: .exact)),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro"),
        ]))
        .frame(width: 640, height: 1100)
        .background(PadzyTheme.ground)
}

#Preview("Blank canvas") {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(true, for: id) }
    return OverviewView(onAddAgent: {})
        .environmentObject(mockViewModel([]))
        .frame(width: 720, height: 520)
        .background(PadzyTheme.ground)
}

#Preview("All unavailable") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code"),
            mockSnapshot(.cursor, name: "Cursor"),
            mockSnapshot(.antigravity, name: "Antigravity"),
        ]))
        .frame(width: 760, height: 1000)
        .background(PadzyTheme.ground)
}
