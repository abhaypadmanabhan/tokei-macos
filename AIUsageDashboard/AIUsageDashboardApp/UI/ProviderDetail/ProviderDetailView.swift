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
    /// §4 `trend(for:)` — ranged daily totals, oldest→newest (the 30d history).
    var trend: [(date: Date, tokens: Int)] = []
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

    @Environment(\.accessibilityReduceMotion) var reduceMotion

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

    var nonCreditsWindows: [QuotaWindow] {
        activeWindows.filter { $0.type != .credits }
    }

    var creditsWindow: QuotaWindow? {
        activeWindows.first { $0.type == .credits }
    }

    /// Whether ANY local token metric was measured — the honest divider between the
    /// full-metrics surface and the plan-only one (mirrors `ProviderCapabilityTier`).
    var hasLocalTokenData: Bool {
        snapshot.todayUsage.confidence != .unavailable
            || snapshot.weekUsage.confidence != .unavailable
            || (snapshot.monthUsage?.confidence).map { $0 != .unavailable } ?? false
            || (snapshot.lifetimeUsage?.confidence).map { $0 != .unavailable } ?? false
    }

    private var isPlanOnly: Bool { !hasLocalTokenData }

    private var todayTotal: Int? { snapshot.todayUsage.totalTokens }

    /// The tightest (highest-utilization) quota window — drives the gauge + the
    /// pace-based insight. Credits are a balance, shown separately, so excluded.
    var tightestWindow: QuotaWindow? {
        nonCreditsWindows
            .compactMap { window in usedPercent(window).map { (window, $0) } }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private var isWide: Bool { containerWidth - Self.hPad * 2 >= 720 }

    private var showQuotaWindows: Bool { !nonCreditsWindows.isEmpty }
    private var showHistory: Bool { hasLocalTokenData }
    private var showSplitSection: Bool { hasLocalTokenData && (hasSplit || todayTotal != nil) }
    private var hasRightColumn: Bool { showHistory || showSplitSection || showAccounts }

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
                if accounts.count > 1 { accountScopeNote }
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
            if showAccounts {
                accountsSection
            } else if showAccountSetupNotice {
                MultiAccountNotice(kind: .claudeSetup)
            }
            if showHistory { dailyHistorySection }
            if showSplitSection { tokenSplitSection }
        }
    }

}

// MARK: - Flow layout

/// Minimal left-to-right wrapping layout (macOS 14 `Layout`) for the mockup's
/// `flex-wrap` rows: the meta grid, the KPI stats group, and the split legend.
/// Wraps to a new line when the next subview would overflow the proposed width.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0 && cursorX + size.width > maxWidth {
                cursorY += rowHeight + vSpacing
                cursorX = 0
                rowHeight = 0
            }
            cursorX += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, cursorX - hSpacing)
        }

        let totalWidth = maxWidth.isFinite ? min(maxWidth, widest) : widest
        return CGSize(width: max(0, totalWidth), height: cursorY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var cursorX: CGFloat = bounds.minX
        var cursorY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX && cursorX + size.width > bounds.maxX {
                cursorY += rowHeight + vSpacing
                cursorX = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), anchor: .topLeading, proposal: ProposedViewSize(size))
            cursorX += size.width + hSpacing
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
