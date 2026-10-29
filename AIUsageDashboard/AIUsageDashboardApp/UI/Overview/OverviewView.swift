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

    /// Usage vs Quota lens — local pane state, animated on change (reduce-motion safe).
    @State var metric: OverviewMetric = .usage

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
        #if DEBUG
        .onAppear { if ProofRoute.wantsQuotaLens { metric = .quota } }
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

                if metric == .usage {
                    agentsSection
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
        if metric == .usage {
            rangedComparison
            LineTrendChart(points: viewModel.overviewTrend, pointDetails: trendPointDetails)
                .frame(height: trendHeight)
                .transition(.opacity)
        } else {
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
    private var agentsSection: some View {
        let models = agentModels
        return VStack(alignment: .leading, spacing: PadzySpace.m) {
            HairlineDivider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                kicker("Agents · \(AnalyticsFormat.rangeTitle(viewModel.range))")
                Spacer(minLength: 8)
            }
            if models.isEmpty {
                Text("No agent used tokens in this range.")
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
        }
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
            Text(AnalyticsFormat.rangeTitle(viewModel.range))
                .font(.mono(size: 13.5))
                .foregroundColor(PadzyTheme.ink5)
            if let delta = viewModel.overviewDelta {
                deltaLine(delta)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Small parts

    private func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.mono(size: 13.5))
            .foregroundColor(PadzyTheme.ink5)
            .lineLimit(1)
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
