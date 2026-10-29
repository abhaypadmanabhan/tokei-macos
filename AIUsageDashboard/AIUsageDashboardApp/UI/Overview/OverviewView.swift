import SwiftUI
import AIUsageDashboardCore

/// The consolidated Overview home, rebuilt to the WP-5 mockup: a Usage/Quota metric
/// selector, a big hero number + one-line context, a full-width trend (or
/// per-agent quota bars), and the usage-lens agent grid. Sections are ruled off by
/// hairlines and named with mono kickers — no card stack, no numbered `NN /` labels.
///
/// All analytics come from the frozen `DashboardViewModel` §4 surface
/// (`overviewTrend / providerSplit / overviewDelta / streak / dailyAverage /
/// utilization / heatmap(for:)`, ranged by `viewModel.range`), plus `MaxxerMath`
/// for the merged-today total and the tightest window. Every widget renders an
/// honest empty state when its source is absent, and unknowns read `—`, never `0`.
struct OverviewView: View {
    // Internal, not private, because `OverviewViewData.swift` holds this view's
    // derivation layer and Swift's `private` is file-scoped. Nothing outside
    // `OverviewView` and that file touches either.
    @EnvironmentObject var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Open a provider's drill-in (wired by `DashboardView` to `openProvider`).
    var onSelectProvider: (ProviderID) -> Void = { _ in }
    /// Open the `+` add-agent sheet (blank-canvas + AGENTS-row primary action).
    var onAddAgent: () -> Void = {}
    /// Open the Settings drawer (a quota row whose live quota is off).
    var onOpenSettings: () -> Void = {}
    /// Open the Value tab (the Cost lens's per-model breakdown).
    var onOpenValue: () -> Void = {}

    /// Usage vs Quota lens — local pane state, animated on change (reduce-motion safe).
    @State var metric: OverviewMetric = .usage

    // MARK: Body

    var body: some View {
        Group {
            if let error = viewModel.errorMessage {
                SurfaceStateView(
                    kind: .error(headline: "Sync failed", detail: error),
                    onRetry: { Task { await viewModel.refresh() } }
                )
            } else if visibleProviders.isEmpty {
                blankCanvas
            } else if viewModel.isLoading && viewModel.snapshots.isEmpty {
                SurfaceStateView(kind: .loading(message: "Reading local logs"))
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if DEBUG
        .onAppear { if ProofRoute.wantsQuotaLens { metric = .quota } }
        .onReceive(NotificationCenter.default.publisher(for: ProofRoute.metricNotification)) { note in
            metric = OverviewMetric(rawValue: note.object as? String ?? "") ?? .usage
        }
        #endif
    }

    private var content: some View {
        GeometryReader { viewport in
            scrollingContent(viewportHeight: viewport.size.height)
        }
    }

    /// The trend takes about a third of the visible height (200…380 pt), so a tall window
    /// gives the chart the room instead of leaving an empty band under short content.
    private func trendHeight(_ viewportHeight: CGFloat) -> CGFloat {
        min(380, max(200, viewportHeight * 0.34))
    }

    private func scrollingContent(viewportHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PadzySpace.xl) {
                OverviewMetricSelector(metric: $metric)

                VStack(alignment: .leading, spacing: PadzySpace.l) {
                    hero
                    mainChart(trendHeight: trendHeight(viewportHeight))
                }
                .animation(reduceMotion ? nil : PadzyMotion.settle, value: metric)

                switch metric {
                case .usage: agentsSection(agentModels)
                case .cost: agentsSection(costAgentModels(viewModel.overviewCost), linksToValue: true)
                case .quota: EmptyView()
                }
            }
            .padding(PadzySpace.xl)
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
                .id(metric)
                .rollingNumber(heroNumericValue, reduceMotion: reduceMotion)
                .accessibilityLabel("\(metric.title), \(heroNumber)")

            Text(heroSubtitle)
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink4)
                .fixedSize(horizontal: false, vertical: true)
                .rollingNumber(Double(activeAgentCount), reduceMotion: reduceMotion)

            // The tightest reading's pace and forecast, same words as its row below.
            if metric == .quota, let pace = viewModel.tightestAccountPace {
                PaceLine(pace: pace, resetAt: viewModel.tightestAccountPressure?.resetAt)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaLine(_ delta: Double) -> some View {
        HStack(spacing: 6) {
            // Direction is carried by the arrow's form; both read in ink (the accent is for
            // state and the primary action, never a change in a number).
            Text(delta >= 0 ? "▲" : "▼")
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink2)
            Text("\(String(format: "%.1f", abs(delta)))%")
                .font(.mono(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .rollingNumber(abs(delta), reduceMotion: reduceMotion)
            Text(AnalyticsFormat.deltaCaption(viewModel.range))
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(delta >= 0 ? "up" : "down") \(String(format: "%.1f", abs(delta))) percent \(AnalyticsFormat.deltaCaption(viewModel.range))")
    }

    // MARK: Main chart / quota bars

    @ViewBuilder
    private func mainChart(trendHeight: CGFloat) -> some View {
        switch metric {
        case .usage:
            rangedComparison
            LineTrendChart(points: viewModel.overviewTrend, pointDetails: trendPointDetails)
                .frame(height: trendHeight)
                .transition(.opacity)
        case .cost:
            let cost = viewModel.overviewCost
            costComparison(cost)
            // Whole cents, so the token chart draws dollars with the same curve and style.
            let priced = cost.trend.compactMap { point in
                point.usd.map { (date: point.date, tokens: Int(($0 * 100).rounded())) }
            }
            LineTrendChart(
                points: priced,
                format: { MaxxerMath.formatUSD(Double($0) / 100) },
                breaks: cost.trend.filter { $0.usd == nil }.map(\.date),
                emptyText: AnalyticsFormat.costChartEmptyText(pricedDays: priced.count)
            )
            .frame(height: trendHeight)
            .transition(.opacity)
        case .quota:
            VStack(alignment: .leading, spacing: PadzySpace.l) {
                AgentQuotaBars(rows: quotaRows, onSelect: onSelectProvider, onOpenSettings: onOpenSettings)
                if !noQuotaSourceProviders.isEmpty {
                    QuietAgentsLine(
                        lead: "No live quota source, local logs only:",
                        providers: noQuotaSourceProviders.map { (id: $0, name: displayName($0)) },
                        onSelect: onSelectProvider
                    )
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: Agents

    /// Agents that used tokens in the range get a tile; the rest share one quiet line.
    private func agentsSection(_ models: [AgentCellModel], linksToValue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: PadzySpace.m) {
            HairlineDivider()
            SectionHeading("Agents \(AnalyticsFormat.rangePhrase(viewModel.range))")
            if models.isEmpty {
                Text("No agent used tokens in this range. Try 30D or 90D above.")
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink3)
            } else {
                AgentGrid(models: models, onSelect: onSelectProvider)
            }
            if !quietInRange.isEmpty {
                QuietAgentsLine(
                    providers: quietInRange.map { (id: $0, name: displayName($0)) },
                    onSelect: onSelectProvider
                )
            }
            if linksToValue {
                Button("Per-model breakdown in Value →") { onOpenValue() }
                    .buttonStyle(.plain)
                    .font(.sans(size: 13, weight: .medium))
                    .foregroundColor(PadzyTheme.ink2)
                    .help("Open Value (⌘2)")
            }
        }
    }

    /// The Cost lens's range total, its like-for-like change, and where pricing starts when
    /// the range reaches further back than the per-model data.
    private func costComparison(_ cost: CostSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(cost.rangeUSD.map { MaxxerMath.formatUSD($0) } ?? "—")
                .font(.mono(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
            Text(AnalyticsFormat.rangePhrase(viewModel.range))
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink4)
            if let delta = cost.delta {
                deltaLine(delta)
            }
            if cost.rangeStartsBeforePricing, let from = cost.pricedFrom {
                Text(AnalyticsFormat.pricedFrom(from))
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink5)
            }
            if cost.unpricedDays > 0 {
                Text("\(cost.unpricedDays) day\(cost.unpricedDays == 1 ? "" : "s") without price data")
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// D12: the ranged delta sits beside the ranged total it was computed from.
    @ViewBuilder
    private var rangedComparison: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(TokenFormatter.format(viewModel.overviewRangedTotal))
                .font(.mono(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .rollingNumber(Double(viewModel.overviewRangedTotal), reduceMotion: reduceMotion)
            Text("tokens \(AnalyticsFormat.rangePhrase(viewModel.range))")
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink4)
            if let delta = viewModel.overviewDelta {
                deltaLine(delta)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Blank canvas

    /// Blank-canvas first-run state: no providers on the canvas yet. Leads with the
    /// `+` — the primary action — instead of a wall of empty provider rows.
    private var blankCanvas: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No agents linked yet")
                .font(.sans(size: 17, weight: .semibold))
                .foregroundColor(PadzyTheme.ink)
            Text("Tokei tracks local AI-coding usage. Link a coding agent to start — detection reads only paths on your disk, nothing leaves your Mac.")
                .font(.sans(size: 15))
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
