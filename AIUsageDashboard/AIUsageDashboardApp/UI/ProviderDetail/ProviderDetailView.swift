import SwiftUI
import AIUsageDashboardCore

/// Unified provider drill-in (WP-5 "P6 Drill-in", mockup outline L273-407). ONE
/// surface for BOTH full-metrics and plan-only providers — no separate pane.
///
/// Top → bottom: tinted brand header (+ optional route chip, plan label,
/// confidence pill) · meta grid · synthesized ◆ insight · gauge + KPI stats ·
/// (plan-only) plan & credits · quota windows · daily history · token split.
/// Wide layouts (≥720pt content) split the quota list (left) from the
/// history/split column (right); everything reflows to a single column and
/// survives a 640×480 window.
///
/// All inputs are plain values fed by `DashboardView`. Every unknown renders "—",
/// never "0"; per-agent tint is DATA colour and the pink `accent` stays STATE-only
/// (progress, the single ◆ marker, the one primary button).
struct ProviderDetailView: View {
    let snapshot: ProviderSnapshot
    /// §4 `trend(for:)` — ranged daily totals, oldest→newest.
    var trend: [(date: Date, tokens: Int)] = []
    /// §4 `thisWeek(for:)`.
    var thisWeek: (peakDayWeekday: Int, peakDayTokens: Int, dailyAverage: Int, delta: Double?)? = nil
    /// §4 `heatmap(for:)` — 7×24, `nil` when the provider has no hourly source.
    var heatmap: [[Int?]]? = nil
    /// §4 `peakHour(for:)`.
    var peakHour: (hour: Int, tokens: Int)? = nil
    var lastSyncedAt: Date? = nil

    /// This provider's value-scorecard entry (api-equivalent $, plan $, multiple,
    /// confidence). `nil` when the provider isn't priceable — drives the "—".
    var value: MaxxerProviderValue? = nil
    /// True when this is the emptiest quota-bearing provider — earns the green
    /// "◆ Route work here" chip.
    var isRouteTarget: Bool = false
    /// Plan/tier text (e.g. "$200/mo · 2× Max accounts"), or `nil`.
    var planLabel: String? = nil
    /// The plan-only "Enable online sync" primary action — wired to Settings by
    /// `DashboardView`; a no-op by default.
    var onEnableOnline: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Full content width (incl. horizontal padding) — drives the ≥720pt two-column
    /// split. Compared against `720 + horizontal padding` so the breakpoint tracks
    /// the *content* box, matching the mockup's inner-content ResizeObserver.
    @State private var containerWidth: CGFloat = 0

    private static let hPad: CGFloat = 28

    // MARK: - Derived state

    private var tier: ProviderCapabilityTier { ProviderCapabilityTier.classify(snapshot) }

    private var activeWindows: [QuotaWindow] {
        snapshot.quotaWindows.filter { $0.confidence != .unavailable }
    }

    private var nonCreditsWindows: [QuotaWindow] {
        activeWindows.filter { $0.type != .credits }
    }

    private var creditsWindow: QuotaWindow? {
        activeWindows.first { $0.type == .credits }
    }

    /// Whether ANY local token metric was measured — the honest divider between the
    /// full-metrics surface and the plan-only one (mirrors `ProviderCapabilityTier`).
    private var hasLocalTokenData: Bool {
        snapshot.todayUsage.confidence != .unavailable
            || snapshot.weekUsage.confidence != .unavailable
            || (snapshot.monthUsage?.confidence).map { $0 != .unavailable } ?? false
            || (snapshot.lifetimeUsage?.confidence).map { $0 != .unavailable } ?? false
    }

    private var isPlanOnly: Bool { !hasLocalTokenData }

    private var todayTotal: Int? { snapshot.todayUsage.totalTokens }

    /// The tightest (highest-utilization) quota window — drives the gauge + the
    /// pace-based insight. Credits are a balance, shown separately, so excluded.
    private var tightestWindow: QuotaWindow? {
        nonCreditsWindows
            .compactMap { window in usedPercent(window).map { (window, $0) } }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private var isWide: Bool { containerWidth - Self.hPad * 2 >= 720 }

    private var showQuotaWindows: Bool { !nonCreditsWindows.isEmpty }
    private var showHistory: Bool { hasLocalTokenData }
    private var showSplitSection: Bool { hasLocalTokenData && (hasSplit || todayTotal != nil) }
    private var hasRightColumn: Bool { showHistory || showSplitSection }

    private static let syncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PadzySpace.xxl) {
                header
                metaGrid
                if let insight = insightSentence { insightBox(insight) }
                gaugeStatsRow
                if isPlanOnly { planCreditsSection }
                bottomRegion
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.hPad)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
                }
            )
        }
        .onPreferenceChange(WidthKey.self) { containerWidth = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }

    // MARK: - 1 · Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderBrandMark.tinted(snapshot.providerID, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(snapshot.displayName)
                        .font(.sans(size: 20, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isRouteTarget { routeChip }
                }
                if let planLabel {
                    Text(planLabel)
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ink4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 12)

            ConfidenceBadge(confidence: headerConfidence)
        }
    }

    private var headerConfidence: MetricConfidence {
        snapshot.todayUsage.confidence != .unavailable
            ? snapshot.todayUsage.confidence
            : (value?.confidence ?? .unavailable)
    }

    private var routeChip: some View {
        HStack(spacing: 6) {
            Text("\u{25C6} Route work here")
                .font(.sans(size: 11, weight: .semibold))
        }
        .foregroundColor(PadzyTheme.good)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                .stroke(PadzyTheme.good.opacity(0.33), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityLabel("Most headroom — route work here")
    }

    // MARK: - 2 · Meta grid

    private var metaGrid: some View {
        FlowLayout(hSpacing: 32, vSpacing: 14) {
            metaBlock(kicker: "Watched file",
                      value: ProviderMetadata.localPaths(for: snapshot.providerID).first ?? "\u{2014}",
                      color: PadzyTheme.ink3)
            metaBlock(kicker: "Last sync",
                      value: lastSyncedAt.map { Self.syncFormatter.string(from: $0) } ?? "NEVER",
                      color: PadzyTheme.ink3)
            metaBlock(kicker: "Capability", value: tier.label, color: PadzyTheme.ink2)
        }
    }

    private func metaBlock(kicker: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(kicker.uppercased())
                .font(.mono(size: 9))
                .tracking(0.9)
                .foregroundColor(PadzyTheme.ink5)
            Text(value)
                .font(.mono(size: 12))
                .foregroundColor(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    // MARK: - 3 · Insight

    /// Synthesizes the one drill sentence from real data, following the mockup's
    /// drill rules (new-design-logic.js ~L312-319). `nil` → the box is omitted.
    private var insightSentence: String? {
        let today = snapshot.todayUsage

        // 1 — cache-read dominance (only when we can name a value multiple).
        if let total = today.totalTokens, total > 0,
           let cacheRead = today.cacheReadTokens, cacheRead > 0,
           let multiple = value?.valueMultiple {
            let share = Double(cacheRead) / Double(total)
            if share >= 0.5 {
                return "\(Int((share * 100).rounded()))% of today's tokens are cache reads — heavy reuse keeps real spend well under the \(MaxxerMath.formatMultiple(multiple)) you'd pay on API."
            }
        }

        // 2 — pay-as-you-go: has tokens, no quota ceiling.
        if nonCreditsWindows.isEmpty, hasLocalTokenData, todayTotal != nil {
            return "Pay-as-you-go, no quota ceiling — spend is metered locally, so there's nothing to run out of."
        }

        // 3 — pace against the tightest window (only when a linear pace is defined).
        if let tightest = tightestWindow, let pct = usedPercent(tightest),
           let verdict = paceVerdict(tightest) {
            let name = insightWindowName(tightest)
            let rounded = Int(pct.rounded())
            switch verdict {
            case .ahead:
                return "Your \(name) is at \(rounded)% and burning ahead of a steady pace — ease off or expect a throttle."
            case .headroom:
                return "Only \(rounded)% of the \(name) is used — plenty of headroom, a good place to route more work."
            case .onPace:
                return "Your \(name) is tracking on pace at \(rounded)% — no action needed."
            }
        }

        // 4 — fallback: weekly volume, worth the plan multiple.
        if hasLocalTokenData, let week = weekTokens {
            if let multiple = value?.valueMultiple {
                return "\(TokenFormatter.format(week)) used this week, worth \(MaxxerMath.formatMultiple(multiple)) against plan."
            }
            return "\(TokenFormatter.format(week)) used this week."
        }

        return nil
    }

    private func insightBox(_ sentence: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\u{25C6}")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.accent)
            Text(sentence)
                .font(.sans(size: 13))
                .foregroundColor(PadzyTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.ground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - 4 · Gauge + stats

    private var gaugeStatsRow: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            HStack(alignment: .center, spacing: PadzySpace.xxxl) {
                if let tightest = tightestWindow, let pct = usedPercent(tightest) {
                    gaugeColumn(tightest, pct: pct)
                }
                statsFlow
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 26)
            HairlineDivider()
        }
    }

    private func gaugeColumn(_ window: QuotaWindow, pct: Double) -> some View {
        VStack(spacing: 10) {
            CircularGauge(percent: pct, label: insightWindowName(window), size: 120)
            if let verdict = paceVerdict(window) {
                Text(verdict.word)
                    .font(.sans(size: 11))
                    .foregroundColor(verdict.color)
            }
        }
        .fixedSize()
    }

    private var statsFlow: some View {
        FlowLayout(hSpacing: 40, vSpacing: 30) {
            statBlock(kicker: "Tokens · today",
                      value: TokenFormatter.format(todayTotal),
                      sub: todayDeltaSub,
                      known: todayTotal != nil)
            statBlock(kicker: "This week",
                      value: TokenFormatter.format(weekTokens),
                      sub: weekDeltaSub,
                      known: weekTokens != nil)
            statBlock(kicker: "Peak hour",
                      value: peakHour.map { AnalyticsFormat.hourLabel($0.hour) } ?? "\u{2014}",
                      sub: peakHour == nil ? "" : "most active",
                      known: peakHour != nil)
            statBlock(kicker: "Plan value",
                      value: MaxxerMath.formatMultiple(value?.valueMultiple),
                      sub: planValueSub,
                      known: value?.valueMultiple != nil)
        }
    }

    private func statBlock(kicker: String, value: String, sub: String, known: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker.uppercased())
                .font(.mono(size: 9.5))
                .tracking(1.0)
                .foregroundColor(PadzyTheme.ink5)
            Text(value)
                .font(.mono(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(known ? PadzyTheme.ink : PadzyTheme.ink5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !sub.isEmpty {
                Text(sub)
                    .font(.sans(size: 11))
                    .foregroundColor(PadzyTheme.ink5)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }

    /// ▲/▼ vs the provider's own trailing-7-day average, when derivable.
    private var todayDeltaSub: String {
        guard let today = todayTotal, let avg = ownWeekAvg, avg > 0 else { return "" }
        let ratio = Double(today) / Double(avg)
        let arrow = ratio >= 1 ? "\u{25B2}" : "\u{25BC}"
        let magnitude = ratio >= 1.8
            ? String(format: "%.1f\u{00D7} its avg", ratio)
            : "\(Int((abs(ratio - 1) * 100).rounded()))% vs avg"
        return "\(arrow) \(magnitude)"
    }

    /// Week-over-week delta, when there's ≥14 days of trend to compare.
    private var weekDeltaSub: String {
        guard trend.count >= 14 else { return "" }
        let last7 = trend.suffix(7).reduce(0) { $0 + $1.tokens }
        let prev7 = trend.dropLast(7).suffix(7).reduce(0) { $0 + $1.tokens }
        guard prev7 > 0 else { return "" }
        let pct = Double(last7 - prev7) / Double(prev7) * 100
        let arrow = pct >= 0 ? "\u{25B2}" : "\u{25BC}"
        return "\(arrow) \(Int(abs(pct).rounded()))% vs prev week"
    }

    private var planValueSub: String {
        guard value?.planMonthlyUSD != nil else { return "no plan cost" }
        return "\(MaxxerMath.formatUSD(value?.apiEquivalentUSD))/mo API-equiv"
    }

    // MARK: - 5 · Plan & credits (plan-only)

    private var planCreditsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel("Plan & credits")

            if let credits = creditsWindow, let display = creditsDisplay(credits) {
                HStack(spacing: 16) {
                    Text(display.barLabel)
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink2)
                        .frame(minWidth: 100, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(PadzyTheme.hairline)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(PadzyTheme.quotaColor(display.fraction * 100))
                                .frame(width: geo.size.width * CGFloat(display.fraction))
                        }
                    }
                    .frame(height: 6)
                    .frame(minWidth: 140, maxWidth: .infinity)
                    Text(display.readout)
                        .font(.mono(size: 13))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                }

                FlowLayout(hSpacing: 40, vSpacing: 20) {
                    ForEach(display.stats, id: \.kicker) { stat in
                        planStatBlock(kicker: stat.kicker, value: stat.value)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\u{2014}")
                    .font(.mono(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
                Text("Token-level usage isn't measured locally for \(snapshot.displayName). The quota above is what Tokei reads honestly.")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: 560, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(PadzyTheme.border2)
            )

            Button(action: onEnableOnline) {
                Text(enableOnlineLabel)
                    .font(.mono(size: 12.5, weight: .semibold))
                    .foregroundColor(PadzyTheme.ground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                            .fill(PadzyTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var enableOnlineLabel: String {
        snapshot.providerID == .cursor ? "Enable online in Settings" : "Enable online sync \u{2192}"
    }

    private func planStatBlock(kicker: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker.uppercased())
                .font(.mono(size: 9.5))
                .tracking(1.0)
                .foregroundColor(PadzyTheme.ink5)
            Text(value)
                .font(.mono(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .fixedSize()
    }

    private struct CreditsDisplay {
        let barLabel: String
        let readout: String
        let fraction: Double
        let stats: [(kicker: String, value: String)]
    }

    /// Preserves the capabilityPane "used" vs "left" nuance: a window reporting
    /// `used` reads as "Credits used"; a balance-style window (only `remaining`)
    /// reads as "Credits left".
    private func creditsDisplay(_ window: QuotaWindow) -> CreditsDisplay? {
        func fmt(_ value: Double) -> String { TokenFormatter.format(Int(value.rounded())) }

        if let used = window.used {
            if let limit = window.limit, limit > 0 {
                return CreditsDisplay(
                    barLabel: "Credits used",
                    readout: "\(fmt(used)) / \(fmt(limit))",
                    fraction: min(1, max(0, used / limit)),
                    stats: [("Credits left", fmt(max(0, limit - used))),
                            ("Credits total", fmt(limit))]
                )
            }
            return CreditsDisplay(
                barLabel: "Credits used",
                readout: fmt(used),
                fraction: min(1, max(0, used / 100)),
                stats: [("Credits used", fmt(used))]
            )
        }

        if let remaining = window.remaining {
            if let limit = window.limit, limit > 0 {
                let used = max(0, limit - remaining)
                return CreditsDisplay(
                    barLabel: "Credits used",
                    readout: "\(fmt(used)) / \(fmt(limit))",
                    fraction: min(1, max(0, used / limit)),
                    stats: [("Credits left", fmt(remaining)),
                            ("Credits total", fmt(limit))]
                )
            }
            return CreditsDisplay(
                barLabel: "Credits left",
                readout: fmt(remaining),
                fraction: 0,
                stats: [("Credits left", fmt(remaining))]
            )
        }

        return nil
    }

    // MARK: - 6/7/8 · Bottom region (2-column ≥720pt)

    @ViewBuilder
    private var bottomRegion: some View {
        if showQuotaWindows && hasRightColumn {
            if isWide {
                HStack(alignment: .top, spacing: 44) {
                    quotaWindowsSection.frame(maxWidth: .infinity, alignment: .leading)
                    rightColumn.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: PadzySpace.xxl) {
                    quotaWindowsSection
                    rightColumn
                }
            }
        } else if hasRightColumn {
            rightColumn
        } else if showQuotaWindows {
            quotaWindowsSection
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 30) {
            if showHistory { dailyHistorySection }
            if showSplitSection { tokenSplitSection }
        }
    }

    // MARK: 6 · Quota windows

    private var quotaWindowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Quota windows")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nonCreditsWindows.enumerated()), id: \.offset) { _, window in
                    quotaRow(window)
                }
            }
            HStack(spacing: 8) {
                Rectangle()
                    .fill(PadzyTheme.ink4)
                    .frame(width: 2, height: 11)
                Text("marker = where a steady, linear burn would sit right now")
                    .font(.sans(size: 10.5))
                    .foregroundColor(PadzyTheme.ink5)
            }
            .padding(.top, 6)
        }
    }

    private func quotaRow(_ window: QuotaWindow) -> some View {
        let pct = usedPercent(window) ?? 0
        let pace = MaxxerMath.pace(usedPercent: pct, windowType: window.type,
                                   resetAt: window.resetAt, now: Date())
        let verdict = pace.map { PaceVerdict(pct: pct, elapsed: $0.elapsedFraction) }

        return HStack(spacing: 14) {
            Text(windowDisplayName(window))
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 88, maxWidth: 140, alignment: .leading)

            quotaFillBar(pct: pct, elapsedFraction: pace?.elapsedFraction, ahead: verdict == .ahead)
                .frame(minWidth: 120, maxWidth: .infinity)

            Text("\(Int(pct.rounded()))%")
                .font(.mono(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .frame(width: 44, alignment: .trailing)

            Text(verdict?.word ?? "\u{2014}")
                .font(.sans(size: 10.5, weight: .semibold))
                .foregroundColor(verdict?.color ?? PadzyTheme.ink5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 64, alignment: .trailing)

            resetCountdown(window.resetAt)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(windowDisplayName(window)) \(Int(pct.rounded())) percent used")
    }

    private func quotaFillBar(pct: Double, elapsedFraction: Double?, ahead: Bool) -> some View {
        let clamped = max(0, min(100, pct))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.muted.opacity(0.3))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.quotaColor(pct))
                    .frame(width: geo.size.width * CGFloat(clamped / 100.0), height: 6)
                if let elapsedFraction {
                    let x = geo.size.width * CGFloat(elapsedFraction)
                    Rectangle()
                        .fill(ahead ? PadzyTheme.accent : PadzyTheme.ink.opacity(0.7))
                        .frame(width: 2, height: 10)
                        .offset(x: min(max(0, x - 1), geo.size.width - 2))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    @ViewBuilder
    private func resetCountdown(_ resetAt: Date?) -> some View {
        if let resetAt {
            if reduceMotion {
                countdownLabel(ProviderOverviewRow.format(until: resetAt, now: Date()))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownLabel(ProviderOverviewRow.format(until: resetAt, now: context.date))
                }
            }
        } else {
            countdownLabel("\u{2014}")
        }
    }

    private func countdownLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono(size: 11))
            .monospacedDigit()
            .foregroundColor(PadzyTheme.ink4)
            .lineLimit(1)
    }

    // MARK: 7 · Daily history

    private var dailyHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Daily history · 30d")
            if trend.count >= 2 {
                LineTrendChart(points: trend, tint: AgentTint.color(snapshot.providerID))
                    .frame(height: 150)
            } else {
                Text("No local token history yet.")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
            }
        }
    }

    // MARK: 8 · Token split

    private var todaySplitSegments: [(name: String, value: Int, shade: Color)] {
        let today = snapshot.todayUsage
        let defs: [(String, Int?, Color)] = [
            ("Input", today.inputTokens, PadzyTheme.ink2),
            ("Cache read", today.cacheReadTokens, PadzyTheme.ink3),
            ("Cache write", today.cacheCreationTokens, PadzyTheme.ink5),
            ("Output", today.outputTokens, Color(hex: "37373E")),
        ]
        return defs.compactMap { name, value, shade in
            guard let value, value > 0 else { return nil }
            return (name, value, shade)
        }
    }

    private var hasSplit: Bool { !todaySplitSegments.isEmpty }

    private var tokenSplitSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Token split · today")
            if hasSplit {
                let segments = todaySplitSegments
                let total = max(1, segments.reduce(0) { $0 + $1.value })
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            Rectangle()
                                .fill(segment.shade)
                                .frame(width: geo.size.width * CGFloat(Double(segment.value) / Double(total)))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                FlowLayout(hSpacing: 24, vSpacing: 10) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        splitLegendItem(segment, total: total)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text("\u{2014}")
                        .font(.mono(size: 16))
                        .foregroundColor(PadzyTheme.ink5)
                    Text("Only aggregate totals available — no per-type split.")
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func splitLegendItem(_ segment: (name: String, value: Int, shade: Color), total: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(segment.shade)
                .frame(width: 8, height: 8)
            Text(segment.name)
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink3)
            Text(TokenFormatter.format(segment.value))
                .font(.mono(size: 12.5))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
            Text(String(format: "%.1f%%", Double(segment.value) / Double(total) * 100))
                .font(.mono(size: 11))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink5)
        }
        .fixedSize()
    }

    // MARK: - Shared helpers

    /// Utilization percent for a window, matching the app's established gauge idiom
    /// (`used / limit` when a limit is present, else `used` is already a percent).
    private func usedPercent(_ window: QuotaWindow) -> Double? {
        guard let used = window.used else { return nil }
        if let limit = window.limit, limit > 0 { return used / limit * 100 }
        return used
    }

    private func paceVerdict(_ window: QuotaWindow) -> PaceVerdict? {
        guard let pct = usedPercent(window),
              let pace = MaxxerMath.pace(usedPercent: pct, windowType: window.type,
                                         resetAt: window.resetAt, now: Date())
        else { return nil }
        return PaceVerdict(pct: pct, elapsed: pace.elapsedFraction)
    }

    /// This week's tokens: the provider's own weekly metric, else the trailing
    /// 7 days of trend, else unknown.
    private var weekTokens: Int? {
        if let week = snapshot.weekUsage.totalTokens { return week }
        guard !trend.isEmpty else { return nil }
        return trend.suffix(7).reduce(0) { $0 + $1.tokens }
    }

    /// The provider's own trailing-7-day average (the 7 days before the latest),
    /// used for the today-vs-average delta. `nil` until there's ≥8 days of trend.
    private var ownWeekAvg: Int? {
        guard trend.count >= 8 else { return nil }
        let prior = Array(trend.dropLast().suffix(7))
        guard !prior.isEmpty else { return nil }
        return prior.reduce(0) { $0 + $1.tokens } / prior.count
    }

    /// Human window label for rows + the gauge (`.label` wins; else a friendly name).
    private func windowDisplayName(_ window: QuotaWindow) -> String {
        if let label = window.label, !label.isEmpty { return label }
        switch window.type {
        case .session: return "Session"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .fiveHour: return "5-hour"
        case .monthly: return "Monthly"
        case .credits: return "Credits"
        case .perModel: return "Per model"
        case .lifetime: return "Lifetime"
        }
    }

    /// Lowercased window phrase for the insight sentence ("weekly window", "quota").
    private func insightWindowName(_ window: QuotaWindow) -> String {
        let base = windowDisplayName(window).lowercased()
        return base.contains("quota") ? base : "\(base) window"
    }
}

// MARK: - Flow layout

/// Minimal left-to-right wrapping layout (macOS 14 `Layout`) for the mockup's
/// `flex-wrap` rows: the meta grid, the KPI stats group, and the split legend.
/// Wraps to a new line when the next subview would overflow the proposed width.
private struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + vSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - hSpacing)
        }

        let totalWidth = maxWidth.isFinite ? min(maxWidth, widest) : widest
        return CGSize(width: max(0, totalWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + vSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Content-width preference so the drill can pick its ≥720pt two-column layout.
private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

private func previewTrend(days: Int) -> [(date: Date, tokens: Int)] {
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000,
                  18_600_000, 9_300_000, 21_400_000, 16_800_000, 12_500_000]
    let today = Calendar.current.startOfDay(for: Date())
    return (0..<days).map { i in
        let daysBack = days - 1 - i
        return (
            date: Calendar.current.date(byAdding: .day, value: -daysBack, to: today) ?? today,
            tokens: values[i % values.count]
        )
    }
}

private func previewSnapshot() -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: .claudeCode,
        displayName: "Claude Code",
        authStatus: .authenticated,
        quotaWindows: [
            QuotaWindow(providerID: .claudeCode, type: .weekly, used: 46, limit: 100,
                        resetAt: Date().addingTimeInterval(3 * 86_400 + 14 * 3600),
                        confidence: .providerReported, source: "preview", label: "Weekly"),
            QuotaWindow(providerID: .claudeCode, type: .fiveHour, used: 22, limit: 100,
                        resetAt: Date().addingTimeInterval(2 * 3600 + 41 * 60),
                        confidence: .providerReported, source: "preview", label: "5-hour"),
        ],
        todayUsage: TokenUsage(inputTokens: 41_200_000, outputTokens: 25_500_000,
                               cacheReadTokens: 402_800_000, cacheCreationTokens: 63_500_000,
                               confidence: .providerReported),
        weekUsage: TokenUsage(inputTokens: 300_000_000, outputTokens: 60_000_000, confidence: .providerReported)
    )
}

#Preview("Full metrics") {
    ProviderDetailView(
        snapshot: previewSnapshot(),
        trend: previewTrend(days: 14),
        peakHour: (hour: 15, tokens: 6_800_000),
        lastSyncedAt: Date(),
        isRouteTarget: false,
        planLabel: "$200/mo · 2× Max accounts"
    )
    .frame(width: 900, height: 1200)
}

#Preview("Plan-only · credits") {
    ProviderDetailView(
        snapshot: ProviderSnapshot(
            providerID: .antigravity,
            displayName: "Antigravity",
            authStatus: .authenticated,
            quotaWindows: [
                QuotaWindow(providerID: .antigravity, type: .credits, used: 340, limit: 500,
                            confidence: .providerReported, source: "preview"),
                QuotaWindow(providerID: .antigravity, type: .weekly, used: 71, limit: 100,
                            resetAt: Date().addingTimeInterval(4 * 86_400),
                            confidence: .providerReported, source: "preview", label: "Gemini · Weekly"),
            ],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        ),
        lastSyncedAt: Date(),
        isRouteTarget: true,
        planLabel: "$5/mo · Google student"
    )
    .frame(width: 720, height: 900)
}

#Preview("Narrow 640") {
    ProviderDetailView(
        snapshot: previewSnapshot(),
        trend: previewTrend(days: 7),
        peakHour: (hour: 11, tokens: 4_100_000),
        lastSyncedAt: Date(),
        planLabel: "$200/mo · 2× Max accounts"
    )
    .frame(width: 640, height: 1200)
}
