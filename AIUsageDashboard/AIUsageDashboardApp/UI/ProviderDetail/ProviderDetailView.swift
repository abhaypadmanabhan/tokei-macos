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
    private var accounts: [ProviderAccountUsage] { snapshot.accounts ?? [] }

    /// Worth a section when there's genuinely more than one account — a single-account setup
    /// would just repeat the headline numbers under a different heading, and its per-account
    /// chart would be the daily-history chart redrawn.
    ///
    /// The one exception: a lone account with a directory we could not read. Then the row is
    /// the only place that says the number above it is missing a piece, which matters more
    /// than not repeating ourselves.
    private var showAccounts: Bool {
        accounts.count > 1 || accounts.contains { !$0.unreadableDirectories.isEmpty }
    }
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

    // MARK: - 4b · Which numbers are all accounts, which are one

    /// The stats above deliberately mix two rules: token counts are a **sum over every
    /// account**, while the gauge and the quota windows are **one account's** — whichever has
    /// the most headroom, because work can be routed there with `CLAUDE_CONFIG_DIR`. Both are
    /// right, and side by side with nothing said they read as one picture: a card showing 50%
    /// while an account sat at 88% is the confusion this line exists to end.
    private var accountScopeNote: some View {
        Text(scopeSentence)
            .font(.sans(size: 15))
            .foregroundColor(PadzyTheme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 640, alignment: .leading)
    }

    private var scopeSentence: String {
        let sum = "Token counts above add up all \(accounts.count) accounts."
        guard tightestWindow != nil else {
            return "\(sum) Per-account numbers are in Accounts below."
        }
        if let account = headlineAccount {
            return "\(sum) The gauge and quota windows are one account — \(account.label), "
                + "the one with the most headroom right now. Per-account numbers are in Accounts below."
        }
        return "\(sum) The gauge and quota windows are a single account's — whichever has the "
            + "most headroom — not all \(accounts.count). Per-account numbers are in Accounts below."
    }

    /// Which account the headline quota came from, re-deriving the provider's "most headroom"
    /// rule — then **checked against** the headline actually on screen, and abandoned if it
    /// doesn't match or if two accounts tie. Naming the wrong account would be worse than
    /// naming none, and this view must not quietly become a second definition of the rule.
    private var headlineAccount: ProviderAccountUsage? {
        let readings = accounts.compactMap { account in
            accountPeak(account).map { (account: account, peak: $0) }
        }
        guard let best = readings.min(by: { $0.peak < $1.peak }),
              let headline = nonCreditsWindows.compactMap({ usedPercent($0) }).max(),
              abs(best.peak - headline) < 0.5,
              readings.filter({ abs($0.peak - best.peak) < 0.5 }).count == 1
        else { return nil }
        return best.account
    }

    /// An account's own utilization: the tightest of its non-credits windows.
    private func accountPeak(_ account: ProviderAccountUsage) -> Double? {
        account.quotaWindows
            .filter { $0.type != .credits }
            .compactMap { usedPercent($0) }
            .max()
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
            if showAccounts {
                accountsSection
            } else if showAccountSetupNotice {
                MultiAccountNotice(kind: .claudeSetup)
            }
            if showHistory { dailyHistorySection }
            if showSplitSection { tokenSplitSection }
        }
    }

    /// The other half of multi-account discovery, and the half no detector can reach.
    ///
    /// Accounts are keyed on the Anthropic identity a directory is signed into, never on the
    /// directory itself (`ClaudeAccount.group`) — so a config directory can only ever report
    /// the **one** account it is currently signed into. Two Anthropic logins used one at a
    /// time out of a single `~/.claude` leave **nothing** on disk to tell them apart, so this
    /// person sees one account and no Accounts section, and there is no cleverness that fixes
    /// it — only saying so. This takes the slot the Accounts section would occupy, which is
    /// exactly where someone asking "why is only one of my accounts here?" is already looking.
    ///
    /// If you are here to change the setup notice's copy, read the `// MARK: Copy` block in
    /// `MultiAccountNotice.swift` first: "one account per directory" is wrong and must not
    /// come back.
    ///
    /// Gated on Claude Code (`CLAUDE_CONFIG_DIR` is its mechanism, not a general one) and on
    /// there being local data at all, so a machine that does not run Claude is never told how
    /// to split Claude accounts. Dismissal lives in the notice and is persisted.
    private var showAccountSetupNotice: Bool {
        snapshot.providerID == .claudeCode && hasLocalTokenData
    }

    // MARK: 6b · Accounts (multi-account providers)

    /// Per-account breakdown for providers where one machine holds several signed-in accounts
    /// (Claude Code, via `CLAUDE_CONFIG_DIR`): one line per account **over time**, on one
    /// shared scale, plus each account's own totals and its own quota.
    ///
    /// The chart is the point of the section. A single row of current numbers can say which
    /// account is bigger today; it cannot say which one has been climbing all week, which is
    /// what "who is spending more" actually means to someone deciding where to work next.
    private var accountsSection: some View {
        let rows = accountRows
        let series = rows.compactMap(\.series)

        return VStack(alignment: .leading, spacing: PadzySpace.m) {
            SectionLabel("Accounts")

            Text(accountsSectionNote)
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)

            if accounts.count > 1 {
                if series.isEmpty {
                    Text("No per-account history yet \u{2014} Claude's local logs haven't recorded a full day for these accounts.")
                        .font(.sans(size: 15))
                        .foregroundColor(PadzyTheme.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    AccountTrendChart(series: series)
                        .frame(height: 170)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let period = accountPeriodLabel { accountRowsHeader(period) }
                ForEach(rows) { row in
                    accountRow(row)
                }
            }
        }
    }

    private var accountsSectionNote: String {
        guard accounts.count > 1 else {
            return "One account, and one of its directories could not be read \u{2014} the totals above are missing whatever is in it."
        }
        let shared = "Each line is one account's own tokens per day, on a shared scale."
        guard let period = accountPeriodLabel else {
            return "\(shared) Daily history below adds every account together."
        }
        // Naming the period twice — here and on the column — is deliberate. The stat tiles at
        // the top of this page are TODAY and these totals are the window; two numbers on one
        // card meaning different things is the whole reason this surface was built.
        return "\(shared) The totals below cover the same \(period) \u{2014} the tiles at the "
            + "top of this page are today. Daily history below adds every account together."
    }

    /// Column header for the account rows. The row's big number is that account's total over
    /// the **chart's** window, and it sits a screen away from a `TOKENS · TODAY` tile — so the
    /// period is stated on the column rather than left to be inferred.
    private func accountRowsHeader(_ period: String) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 8)
            Text("tokens \u{00B7} \(period)")
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink5)
                .lineLimit(1)
            Text("share")
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink5)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.bottom, PadzySpace.xs)
    }

    /// The span the rows and the chart both cover, in words, derived from the window they are
    /// actually drawn from — so the label cannot claim a period the numbers do not cover.
    private var accountPeriodLabel: String? {
        guard let window = accountWindow else { return nil }
        let days = (Calendar.current.dateComponents(
            [.day], from: window.lowerBound, to: window.upperBound
        ).day ?? 0) + 1
        return days <= 1 ? "today" : "last \(days) days"
    }

    /// One account's row: its identity (and the directories folded into it), its tokens over
    /// the same window as the chart, its share of the accounts' total, and its **own** quota
    /// — the number the gauge above is not, unless this happens to be the freest account.
    private func accountRow(_ row: AccountRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                StrokeSwatch(color: row.color, dash: row.dash)
                    .opacity(row.series == nil ? 0.35 : 1)
                Text(row.account.label)
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(TokenFormatter.format(row.rangeTokens))
                    .font(.mono(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(row.rangeTokens == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
                Text(row.shareLabel)
                    .font(.mono(size: 13.5))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink5)
                    .frame(width: 48, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 10) {
                // One directory per line, never joined. Joined with a separator and truncated
                // in the middle, two long paths lose exactly the separator and read as one
                // path — so the merged identity looks like a directory that vanished, which
                // is the thing this line exists to prevent.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(row.directoryLabels, id: \.self) { directory in
                        Text(directory)
                            .font(.mono(size: 13.5))
                            .foregroundColor(PadzyTheme.ink5)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Text("own quota")
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.ink5)
                Text(row.peak.map { "\(Int($0.rounded()))%" } ?? "\u{2014}")
                    .font(.mono(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(row.peak == nil ? PadzyTheme.ink5 : PadzyTheme.ink2)
                    .frame(width: 44, alignment: .trailing)
            }

            if !row.account.unreadableDirectories.isEmpty {
                Text(Self.unreadableNotice(row.account.unreadableDirectories))
                    .font(.sans(size: 15))
                    .foregroundColor(PadzyTheme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, PadzySpace.s)
        .accessibilityElement(children: .combine)
    }

    /// Names the directory, not just the fact — "something failed" sends nobody anywhere.
    private static func unreadableNotice(_ paths: [String]) -> String {
        let names = paths.map(Self.abbreviated).joined(separator: ", ")
        let subject = paths.count == 1 ? "its usage is" : "their usage is"
        return "\(names) couldn't be read on this refresh, so \(subject) missing from these numbers."
    }

    // MARK: 6b · Per-account series

    private struct AccountRow: Identifiable {
        let account: ProviderAccountUsage
        let color: Color
        let dash: [CGFloat]
        let series: AccountTrendChart.Series?
        /// Tokens inside the chart's window. `nil` when this account has no series at all.
        let rangeTokens: Int?
        let share: Double?
        let peak: Double?

        var id: String { account.id }

        var shareLabel: String {
            guard let share else { return "\u{2014}" }
            return "\(Int((share * 100).rounded()))%"
        }

        /// The `CLAUDE_CONFIG_DIR`s folded into this one identity. Two of them is exactly why
        /// three directories on this machine list as two accounts, and without it the second
        /// row looks like a directory that vanished.
        ///
        /// A list, not a joined string: rendered one per line, a long path can only truncate
        /// inside itself. Joined with a separator and truncated in the middle, two long paths
        /// lose exactly the separator and read as a single directory.
        var directoryLabels: [String] {
            let names = account.configDirectories.map(ProviderDetailView.abbreviated)
            return names.isEmpty ? [ProviderDetailView.abbreviated(account.id)] : names
        }
    }

    /// `~/.claude-account-2` rather than `/Users/me/.claude-account-2` — the home prefix is
    /// the same on every row and eats the width the distinguishing part needs.
    private static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// The day span the per-account chart covers: the aggregate `trend`'s own span, so this
    /// chart and the daily-history chart below it always describe the same window — including
    /// when the user moves the range control, which this view never sees directly. Falls back
    /// to whatever the accounts recorded when the aggregate has no history to align to.
    private var accountWindow: ClosedRange<Date>? {
        let calendar = Calendar.current
        if let first = trend.first?.date, let last = trend.last?.date, first <= last {
            return calendar.startOfDay(for: first)...calendar.startOfDay(for: last)
        }
        let days = accounts
            .flatMap { ($0.dailyTotals ?? [:]).keys }
            .map { calendar.startOfDay(for: $0) }
        guard let first = days.min(), let last = days.max() else { return nil }
        return first...last
    }

    /// Per-account rows, biggest spender first — the answer to the question is the reading
    /// order. Colours stay keyed to the provider's own account order, so a row's line does
    /// not change colour when the ranking flips.
    private var accountRows: [AccountRow] {
        let calendar = Calendar.current
        let tint = AgentTint.color(snapshot.providerID)
        let window = accountWindow

        let rows: [AccountRow] = accounts.enumerated().map { index, account in
            let color = AccountSeriesStyle.color(index, tint: tint)
            let dash = AccountSeriesStyle.dash(index)
            guard let window, let totals = account.dailyTotals, !totals.isEmpty else {
                return AccountRow(account: account, color: color, dash: dash, series: nil,
                                  rangeTokens: nil, share: nil, peak: accountPeak(account))
            }

            var byDay: [Date: Int] = [:]
            for (date, tokens) in totals {
                byDay[calendar.startOfDay(for: date), default: 0] += tokens
            }

            var points: [AccountTrendChart.Point] = []
            var day = window.lowerBound
            while day <= window.upperBound {
                points.append(AccountTrendChart.Point(date: day, tokens: byDay[day] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }

            let total = points.reduce(0) { $0 + $1.tokens }
            // An account with nothing inside the window gets no line: a flat zero drawn
            // across the whole chart reads as "measured, and it was zero" — which we know,
            // but it also buries the account that did the work under a second stroke.
            let series = total > 0
                ? AccountTrendChart.Series(id: account.id, label: account.label,
                                           color: color, dash: dash, points: points)
                : nil
            return AccountRow(account: account, color: color, dash: dash, series: series,
                              rangeTokens: total, share: nil, peak: accountPeak(account))
        }

        let grandTotal = rows.compactMap(\.rangeTokens).reduce(0, +)
        return rows
            .map { row in
                guard grandTotal > 0, let tokens = row.rangeTokens else { return row }
                return AccountRow(account: row.account, color: row.color, dash: row.dash,
                                  series: row.series, rangeTokens: tokens,
                                  share: Double(tokens) / Double(grandTotal), peak: row.peak)
            }
            .sorted { ($0.rangeTokens ?? -1) > ($1.rangeTokens ?? -1) }
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

/// Two accounts with genuinely different daily shapes and different quota — the machine this
/// was built for. `default` spends more but has the headroom; `account-1` is the 88% the card
/// used to hide behind a 50%.
private func previewAccounts(_ count: Int, days: Int) -> [ProviderAccountUsage] {
    let today = Calendar.current.startOfDay(for: Date())
    let shapes: [[Int]] = [
        [12_000_000, 31_000_000, 8_400_000, 44_000_000, 27_000_000, 51_000_000, 19_000_000],
        [4_100_000, 3_200_000, 9_800_000, 2_400_000, 14_000_000, 6_100_000, 11_200_000],
        [900_000, 2_100_000, 400_000, 3_300_000, 1_200_000, 2_800_000, 700_000],
    ]
    let peaks: [Double] = [50, 88, 31]
    return (0..<count).map { index in
        var totals: [Date: Int] = [:]
        for back in 0..<days {
            let date = Calendar.current.date(byAdding: .day, value: -back, to: today) ?? today
            totals[date] = shapes[index % shapes.count][back % 7]
        }
        return ProviderAccountUsage(
            id: index == 0 ? "/Users/preview/.claude" : "/Users/preview/.claude-account-\(index)",
            label: index == 0 ? "default" : "account-\(index)",
            quotaWindows: [
                QuotaWindow(providerID: .claudeCode, type: .weekly, used: peaks[index % peaks.count],
                            limit: 100, resetAt: Date().addingTimeInterval(3 * 86_400),
                            confidence: .providerReported, source: "preview", label: "Weekly"),
            ],
            todayUsage: TokenUsage(inputTokens: 1_000_000, outputTokens: 400_000,
                                   confidence: .providerReported),
            dailyTotals: totals,
            configDirectories: index == 0
                ? ["/Users/preview/.claude", "/Users/preview/.claude-account-2"]
                : ["/Users/preview/.claude-account-\(index)"],
            unreadableDirectories: []
        )
    }
}

private func previewMultiAccountSnapshot(_ count: Int, unreadable: Bool = false) -> ProviderSnapshot {
    var accounts = previewAccounts(count, days: 14)
    if unreadable, let first = accounts.first {
        accounts[0] = ProviderAccountUsage(
            id: first.id, label: first.label, quotaWindows: first.quotaWindows,
            todayUsage: first.todayUsage, dailyTotals: first.dailyTotals,
            configDirectories: first.configDirectories,
            unreadableDirectories: ["/Users/preview/.claude-account-2"]
        )
    }
    let base = previewSnapshot()
    return ProviderSnapshot(
        providerID: base.providerID,
        displayName: base.displayName,
        authStatus: base.authStatus,
        quotaWindows: base.quotaWindows,
        todayUsage: base.todayUsage,
        weekUsage: base.weekUsage,
        accounts: accounts
    )
}

#Preview("Two accounts") {
    ProviderDetailView(
        snapshot: previewMultiAccountSnapshot(2),
        trend: previewTrend(days: 14),
        peakHour: (hour: 15, tokens: 6_800_000),
        lastSyncedAt: Date(),
        planLabel: "$200/mo \u{00B7} 2\u{00D7} Max accounts"
    )
    .frame(width: 980, height: 1200)
}

#Preview("Three accounts · narrow") {
    ProviderDetailView(
        snapshot: previewMultiAccountSnapshot(3, unreadable: true),
        trend: previewTrend(days: 14),
        lastSyncedAt: Date()
    )
    .frame(width: 640, height: 1300)
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
