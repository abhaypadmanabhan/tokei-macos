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
    // Internal, not private, because `OverviewViewData.swift` holds this view's
    // derivation layer and Swift's `private` is file-scoped. Nothing outside
    // `OverviewView` and that file touches either.
    @EnvironmentObject var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Open a provider's drill-in (wired by `DashboardView` to `openProvider`).
    var onSelectProvider: (ProviderID) -> Void = { _ in }
    /// Open the `+` add-agent sheet (blank-canvas + AGENTS-row primary action).
    var onAddAgent: () -> Void = {}

    /// Usage vs Quota lens — local pane state, animated on change (reduce-motion safe).
    @State var metric: OverviewMetric = .usage
    /// Measured content width, drives the split row's side-by-side ↔ stacked reflow.
    @State private var contentWidth: CGFloat = 0

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

    private func deltaLine(_ delta: Double) -> some View {
        HStack(spacing: 6) {
            Text("\(delta >= 0 ? "▲" : "▼") \(String(format: "%.1f", abs(delta)))%")
                .font(.mono(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(delta >= 0 ? PadzyChartPalette.deltaUp : PadzyChartPalette.deltaDown)
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
            LineTrendChart(points: viewModel.overviewTrend, pointDetails: trendPointDetails)
                .frame(height: 200)
                .transition(.opacity)
        } else {
            AgentQuotaBars(rows: quotaRows, onConnect: onSelectProvider)
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
            ActivityHeatmap(cells: heatCells)
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
