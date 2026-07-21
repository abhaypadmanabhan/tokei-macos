import SwiftUI
import AIUsageDashboardCore

/// The value surface (#23 UI half + #41): what your paid plans are actually
/// worth against what the same month of tokens would cost at public API rates.
///
/// WP-5 rebuild to the "Tokei Dashboard" mockup (outline L167-219): an 84pt mono
/// hero multiple with the tier chip inline, a plain-language "$api from $plan"
/// sentence, one ◆ insight line, then a clean hairline-row grid — no card stack,
/// no fixed-width table. Every row drills into the provider (or, when a plan cost
/// is missing, jumps to Settings to fix it).
///
/// Reads the frozen Maxxer contract (Bible §4) through
/// `MaxxerValueEngine.scorecard(snapshots:planCosts:now:)` and the existing
/// `MaxxerMath.lifetimeTotal` API — no Core edits.
///
/// Editorial contract: dollar figures and multiples are `ink` (data, not state);
/// the single pink accent is spent only on the ◆ insight marker and the empty
/// state's primary action; the tier chip uses semantic good/warn status colour,
/// never the accent; every unknown renders `—`, never a confident zero. There is
/// no animation on this surface, so Reduce Motion has nothing to suppress.
struct ValueView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Routes to the Settings drawer, where the plan-cost fields live.
    var onOpenPlanCosts: () -> Void = {}

    /// Drills into a provider's detail. Wired to `DashboardView.openProvider`.
    var onSelectProvider: (ProviderID) -> Void = { _ in }

    /// Injectable so previews can exercise the loaded state without writing into
    /// the developer's real `UserDefaults`. Ships reading `.standard`.
    var planCosts: MaxxerPlanCostStore = MaxxerPlanCostStore()

    /// Plan costs live in `UserDefaults`, which publishes nothing SwiftUI tracks.
    /// Bumped on `didChangeNotification` so an edit made in Settings is reflected
    /// the moment this pane is shown again, not one navigation late.
    @State private var storeRevision = 0

    // MARK: Snapshot-derived state

    private var visibleSnapshots: [ProviderSnapshot] {
        viewModel.snapshots.filter { !ProviderVisibility.isHidden($0.providerID) }
    }

    private var hiddenProviders: Set<ProviderID> {
        Set(ProviderID.allCases.filter { ProviderVisibility.isHidden($0) })
    }

    private var scorecard: MaxxerScorecard {
        MaxxerValueEngine.scorecard(
            snapshots: visibleSnapshots,
            planCosts: planCosts,
            now: Date()
        )
    }

    private var lifetime: MaxxerMath.LifetimeTotal? {
        MaxxerMath.lifetimeTotal(in: viewModel.snapshots, hiddenProviders: hiddenProviders)
    }

    /// True only when the user has never entered a plan cost for ANY visible
    /// provider — the one state where the whole surface is uncomputable and the
    /// right answer is a CTA rather than a table of dashes.
    private var hasAnyPlanCost: Bool {
        scorecard.providers.contains { $0.planMonthlyUSD != nil }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                storeRevision &+= 1
            }
    }

    // MARK: State routing

    /// Error → loading → no-plan-cost → loaded, matching the precedence the
    /// provider-detail pane already established.
    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            SurfaceStateView(
                kind: .error(headline: "Sync failed", detail: errorMessage),
                onRetry: { Task { await viewModel.refresh() } }
            )
        } else if visibleSnapshots.isEmpty && viewModel.isLoading {
            SurfaceStateView(kind: .loading(message: "Reading local logs"))
        } else if visibleSnapshots.isEmpty {
            SurfaceStateView(
                kind: .empty(
                    headline: "No agents linked",
                    hint: "Link a coding agent first — value is measured against the tokens your agents actually spend."
                )
            )
        } else if !hasAnyPlanCost {
            noPlanCostState
        } else {
            loadedState
        }
    }

    // MARK: No plan cost

    /// The surface's real empty state: agents are connected, but Tokei has no idea
    /// what the user pays, so every multiple would be `—`. Leads with the action
    /// that fixes it, then still shows the lifetime total so the pane isn't bare.
    private var noPlanCostState: some View {
        VStack(alignment: .leading, spacing: 14) {
            SurfaceStateView(
                kind: .empty(
                    headline: "No plan costs set",
                    hint: "Tokei can't say what your plans are worth until it knows what they cost. Add each agent's monthly price — it stays on this Mac like everything else."
                ),
                compact: true
            )
            planCostCTA
            lifetimeCard
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The single primary action on this surface — the one sanctioned accent fill.
    private var planCostCTA: some View {
        Button(action: onOpenPlanCosts) {
            Text("SET PLAN COSTS →")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.ground)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .fill(PadzyTheme.accent)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set plan costs in Settings")
    }

    // MARK: Loaded

    private var loadedState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Plan value · this month")

                hero
                    .padding(.top, 16)

                summarySentence
                    .padding(.top, 18)

                if let insight = insightText {
                    insightBox(insight)
                        .padding(.top, 16)
                }

                valueRows
                    .padding(.top, 28)

                excludedFootnote
                    .padding(.top, 18)
            }
            .padding(.horizontal, PadzySpace.xxl)
            .padding(.top, 34)
            .padding(.bottom, PadzySpace.xxxl)
        }
    }

    /// The 84pt headline multiple with the tier chip sitting inline to its right —
    /// the mockup's hero. The multiple is the surface's one big number; the chip is
    /// the only colour on the pane (semantic good/warn, never the accent).
    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(MaxxerMath.formatMultiple(scorecard.totalValueMultiple))
                .font(.mono(size: 84, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(scorecard.totalValueMultiple == nil ? PadzyTheme.muted : PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Plan value \(MaxxerMath.formatMultiple(scorecard.totalValueMultiple))")

            if let tier = scorecard.tier {
                TierChip(tier: tier)
            }

            Spacer(minLength: 0)
        }
    }

    /// "You're getting $833.40 of API-equivalent usage from $245.00 in plans across
    /// N agents." Dollar figures are ink mono (data); the prose is muted sans.
    /// The mockup's "▲ 0.3× vs last month" delta is intentionally dropped — Core
    /// keeps no month-over-month history, and a fabricated delta would break the
    /// "never a confident number we don't have" rule.
    private var summarySentence: some View {
        let api = MaxxerMath.formatUSD(scorecard.totalAPIEquivalentUSD)
        let plan = MaxxerMath.formatUSD(scorecard.totalPlanUSD)
        let n = pricedCount
        return (
            Text("You're getting ").foregroundColor(PadzyTheme.muted)
            + Text(api).font(.mono(size: 15)).foregroundColor(PadzyTheme.ink)
            + Text(" of API-equivalent usage from ").foregroundColor(PadzyTheme.muted)
            + Text(plan).font(.mono(size: 15)).foregroundColor(PadzyTheme.ink)
            + Text(" in plans across \(n) agent\(n == 1 ? "" : "s").").foregroundColor(PadzyTheme.muted)
        )
        .font(.sans(size: 15))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// One plain-language read on the numbers, in a hairline-bounded box with the
    /// single accent spent on the ◆ marker.
    private func insightBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("◆")
                .font(.mono(size: 13))
                .foregroundColor(PadzyTheme.accent)
            Text(text)
                .font(.sans(size: 13))
                .foregroundColor(PadzyTheme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 560, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PadzyTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: Rows

    private var valueRows: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            ForEach(rows) { row in
                ValueRow(
                    value: row.value,
                    displayName: row.displayName,
                    providerID: row.providerID,
                    onDrill: { if let id = row.providerID { onSelectProvider(id) } },
                    onSetPlanCost: onOpenPlanCosts
                )
                HairlineDivider()
            }
            ValueTotalRow(scorecard: scorecard)
        }
    }

    // MARK: Footnote

    /// One line naming what the total leaves out and why, with the lifetime total
    /// folded onto the tail (mockup). Preserves the #41 lifetime binding without a
    /// separate card. `nil` categories simply drop out of the sentence.
    @ViewBuilder
    private var excludedFootnote: some View {
        let text = footnoteText
        if !text.isEmpty {
            Text(text)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.ink5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }

    private var footnoteText: String {
        var clauses: [String] = []
        if !unpricedRows.isEmpty {
            clauses.append("\(unpricedNames) (usage, no plan cost)")
        }
        let noData = rows.filter { $0.value.planMonthlyUSD != nil && $0.value.apiEquivalentUSD == nil }
        if !noData.isEmpty {
            let names = joinNames(noData.map(\.displayName))
            clauses.append("\(names) (plan set, no token data)")
        }

        var sentence = ""
        if !clauses.isEmpty {
            sentence = "Excluded from the total: \(clauses.joined(separator: " · "))."
        }
        if let lifetime {
            let prefix = lifetime.usedDailyFallback ? "≈" : ""
            let tail = "\(prefix)\(TokenFormatter.format(lifetime.tokens)) tokens tracked lifetime."
            sentence = sentence.isEmpty ? tail : "\(sentence) \(tail)"
        }
        return sentence
    }

    // MARK: Rows model

    private struct Row: Identifiable {
        let value: MaxxerProviderValue
        let providerID: ProviderID?
        let displayName: String
        var id: String { value.providerID }
    }

    /// Highest value multiple first; unmeasurable agents sink to the bottom.
    private var rows: [Row] {
        scorecard.providers
            .map { value in
                let id = ProviderID(rawValue: value.providerID)
                let name = id.flatMap { viewModel.snapshot(for: $0)?.displayName }
                    ?? value.providerID.replacingOccurrences(of: "_", with: " ").capitalized
                return Row(value: value, providerID: id, displayName: name)
            }
            .sorted { ($0.value.valueMultiple ?? -1) > ($1.value.valueMultiple ?? -1) }
    }

    /// Agents with priced usage but no user-entered plan cost — excluded from the
    /// totals (paired-only), so the headline understates their spend.
    private var unpricedRows: [Row] {
        rows.filter { $0.value.apiEquivalentUSD != nil && $0.value.planMonthlyUSD == nil }
    }

    private var unpricedNames: String { joinNames(unpricedRows.map(\.displayName)) }

    private var pricedCount: Int {
        scorecard.providers.filter { $0.planMonthlyUSD != nil }.count
    }

    /// The single insight line: names the one plan that is underwater, or — if all
    /// earn out — the thinnest one, so the reader always leaves with one takeaway.
    private var insightText: String? {
        let priced = rows.filter { $0.value.valueMultiple != nil }
        guard !priced.isEmpty else { return nil }

        let under = priced
            .filter { ($0.value.valueMultiple ?? 0) < 1 }
            .sorted { ($0.value.valueMultiple ?? 0) < ($1.value.valueMultiple ?? 0) }
        if let worst = under.first {
            return "\(worst.displayName) is only returning \(MaxxerMath.formatMultiple(worst.value.valueMultiple)) — you're paying more than you're getting back. Worth a downgrade look."
        }

        let thinnest = priced.min { ($0.value.valueMultiple ?? .infinity) < ($1.value.valueMultiple ?? .infinity) }
        if let thinnest {
            return "Every plan is earning out. Your thinnest is \(thinnest.displayName) at \(MaxxerMath.formatMultiple(thinnest.value.valueMultiple)) — still well worth it."
        }
        return nil
    }

    private func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and \(names[names.count - 1])"
        }
    }

    // MARK: Lifetime (#41 · no-plan-cost state only)

    private var lifetimeCard: some View {
        SectionCard("Lifetime", trailing: {
            if let lifetime {
                ConfidenceBadge(confidence: lifetime.confidence, compact: true)
            }
        }) {
            if let lifetime {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(TokenFormatter.format(lifetime.tokens))
                            .font(.mono(size: 40))
                            .monospacedDigit()
                            .foregroundColor(PadzyTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        Text("TOKENS ALL-TIME")
                            .font(.mono(size: 11))
                            .tracking(11 * 0.08)
                            .foregroundColor(PadzyTheme.muted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(lifetime.tokens) tokens all-time")

                    Text(lifetimeNote(lifetime))
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SurfaceStateView(
                    kind: .empty(
                        headline: "No all-time data",
                        hint: "No linked agent reports a lifetime total or keeps daily logs yet."
                    ),
                    compact: true
                )
            }
        }
    }

    /// Says out loud which of the two sources produced the number, because a
    /// daily-log sum is a floor and a provider-reported lifetime is not.
    private func lifetimeNote(_ lifetime: MaxxerMath.LifetimeTotal) -> String {
        let agents = "\(lifetime.contributingProviders) agent\(lifetime.contributingProviders == 1 ? "" : "s")"
        if lifetime.usedDailyFallback {
            return "Across \(agents). Agents that report no all-time figure are summed from their daily logs instead, so this is a floor — real all-time usage is at least this high."
        }
        return "Across \(agents), each reporting its own all-time total."
    }
}

// MARK: - Tier

extension MaxxerTier {
    /// Caps display label for the chip. Kept in the UI layer on purpose — the
    /// frozen §4 contract carries no presentation strings.
    var displayName: String {
        switch self {
        case .idle: return "IDLE"
        case .warming: return "WARMING"
        case .breakEven: return "BREAK EVEN"
        case .maxxing: return "MAXXING"
        case .goblinMode: return "GOBLIN MODE"
        }
    }

    /// One line explaining what the tier means in plan-value terms.
    var blurb: String {
        switch self {
        case .idle: return "Barely touching what you pay for."
        case .warming: return "Below break-even on your plans."
        case .breakEven: return "Your plans have paid for themselves."
        case .maxxing: return "Well past break-even."
        case .goblinMode: return "5× your plan cost or better."
        }
    }

    /// Semantic status colour for the chip: amber below break-even (a nudge to
    /// review), green once the plan has paid for itself. Never the pink accent.
    var statusColor: Color {
        switch self {
        case .idle, .warming: return PadzyTheme.warn
        case .breakEven, .maxxing, .goblinMode: return PadzyTheme.good
        }
    }
}

/// Tier chip (mockup): a colour-bordered, colour-labelled mono pill in the tier's
/// semantic status hue. The word carries the meaning; colour only reinforces it,
/// so the tier is never signalled by colour alone.
struct TierChip: View {
    let tier: MaxxerTier

    var body: some View {
        Text(tier.displayName)
            .font(.mono(size: 11, weight: .semibold))
            .tracking(11 * 0.1)
            .foregroundColor(tier.statusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                    .stroke(tier.statusColor.opacity(0.4), lineWidth: 1)
            )
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tier: \(tier.displayName). \(tier.blurb)")
    }
}

// MARK: - Rows

/// Shared trailing-column widths so every row and the total line up on one grid.
private enum ValueColumn {
    static let multiple: CGFloat = 60
    static let spacing: CGFloat = 12
}

/// One agent's value row — a button that drills into the provider, or (when the
/// agent has usage but no plan cost) jumps to Settings to set it. Wide layout is
/// the three-column grid; below the 640pt minimum the dollar detail wraps to a
/// second line rather than truncating, so real numbers stay visible.
private struct ValueRow: View {
    let value: MaxxerProviderValue
    let displayName: String
    let providerID: ProviderID?
    let onDrill: () -> Void
    let onSetPlanCost: () -> Void

    /// Usage is priced but the user never entered a plan cost — the one row whose
    /// primary action is "fix the missing price", not "drill in".
    private var isUnpriced: Bool {
        value.apiEquivalentUSD != nil && value.planMonthlyUSD == nil
    }

    private var isEstimated: Bool { value.confidence == .estimated }

    var body: some View {
        Button(action: isUnpriced ? onSetPlanCost : onDrill) {
            ViewThatFits(in: .horizontal) {
                wide
                narrow
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isUnpriced ? "Opens Settings to set a plan cost" : "Opens \(displayName) detail")
    }

    private var wide: some View {
        HStack(spacing: ValueColumn.spacing) {
            agentCell
            middle
            multipleCell
        }
    }

    private var narrow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: ValueColumn.spacing) {
                agentCell
                multipleCell
            }
            middle
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var agentCell: some View {
        HStack(spacing: 11) {
            if let providerID {
                ProviderBrandMark.tinted(providerID, size: 22)
            }
            Text(displayName)
                .font(.sans(size: 14, weight: .medium))
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The `$plan → $api` middle column, or the accent "Set plan cost →" cue when
    /// the plan price is missing. The API figure carries the dotted confidence
    /// underline when it is an estimate, matching the Overview grid.
    @ViewBuilder
    private var middle: some View {
        if isUnpriced {
            Text("Set plan cost →")
                .font(.sans(size: 12, weight: .semibold))
                .foregroundColor(PadzyTheme.accent)
        } else {
            HStack(spacing: 6) {
                Text("\(MaxxerMath.formatUSD(value.planMonthlyUSD)) →")
                    .font(.mono(size: 12))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.muted)
                apiFigure
            }
        }
    }

    @ViewBuilder
    private var apiFigure: some View {
        let text = MaxxerMath.formatUSD(value.apiEquivalentUSD)
        if isEstimated {
            VStack(spacing: 2) {
                Text(text)
                    .font(.mono(size: 12))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.muted)
                DottedUnderline()
            }
            .fixedSize()
            .help("Estimated — not directly reported")
        } else {
            Text(text)
                .font(.mono(size: 12))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.muted)
        }
    }

    private var multipleCell: some View {
        Text(MaxxerMath.formatMultiple(value.valueMultiple))
            .font(.mono(size: 20, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(value.valueMultiple == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
            .lineLimit(1)
            .frame(width: ValueColumn.multiple, alignment: .trailing)
    }

    private var accessibilityText: String {
        let plan = value.planMonthlyUSD == nil ? "no plan cost set" : "plan \(MaxxerMath.formatUSD(value.planMonthlyUSD))"
        let api = value.apiEquivalentUSD == nil ? "API equivalent unavailable" : "API equivalent \(MaxxerMath.formatUSD(value.apiEquivalentUSD))"
        let multiple = value.valueMultiple == nil ? "value multiple unavailable" : "\(MaxxerMath.formatMultiple(value.valueMultiple)) plan value"
        return "\(displayName): \(plan), \(api), \(multiple). Confidence \(value.confidence.displayName)."
    }
}

/// The total row — same grid, but a non-tappable summary. The multiple keeps ink
/// weight; the dollar totals stay ink (data, not state).
private struct ValueTotalRow: View {
    let scorecard: MaxxerScorecard

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wide
            narrow
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Total: plan \(MaxxerMath.formatUSD(scorecard.totalPlanUSD)), "
            + "API equivalent \(MaxxerMath.formatUSD(scorecard.totalAPIEquivalentUSD)), "
            + "\(MaxxerMath.formatMultiple(scorecard.totalValueMultiple)) plan value."
        )
    }

    private var wide: some View {
        HStack(spacing: ValueColumn.spacing) {
            totalLabel
            totals
            multipleCell
        }
    }

    private var narrow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: ValueColumn.spacing) {
                totalLabel
                multipleCell
            }
            totals
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var totalLabel: some View {
        Text("TOTAL")
            .font(.mono(size: 10))
            .tracking(10 * 0.12)
            .foregroundColor(PadzyTheme.ink5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totals: some View {
        Text("\(MaxxerMath.formatUSD(scorecard.totalPlanUSD)) → \(MaxxerMath.formatUSD(scorecard.totalAPIEquivalentUSD))")
            .font(.mono(size: 12))
            .monospacedDigit()
            .foregroundColor(PadzyTheme.ink3)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var multipleCell: some View {
        Text(MaxxerMath.formatMultiple(scorecard.totalValueMultiple))
            .font(.mono(size: 20, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(scorecard.totalValueMultiple == nil ? PadzyTheme.ink5 : PadzyTheme.ink)
            .lineLimit(1)
            .frame(width: ValueColumn.multiple, alignment: .trailing)
    }
}

// MARK: - Previews

/// Previews write plan costs into a throwaway suite so a developer's real
/// settings are never touched by opening a canvas.
@MainActor
private func previewPlanCosts(_ costs: [ProviderID: Double]) -> MaxxerPlanCostStore {
    let defaults = UserDefaults(suiteName: "ai.padzy.tokei.previews.value")!
    let store = MaxxerPlanCostStore(defaults: defaults)
    for id in ProviderID.allCases {
        store.setMonthlyUSD(costs[id], for: id.rawValue)
    }
    return store
}

@MainActor
private func previewVM(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    return vm
}

@MainActor
private func previewSnapshot(
    _ id: ProviderID,
    name: String,
    month: TokenUsage? = nil,
    lifetime: TokenUsage? = nil,
    dailyTotals: [Date: Int]? = nil
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: [],
        todayUsage: .unavailable,
        weekUsage: .unavailable,
        monthUsage: month,
        lifetimeUsage: lifetime,
        warnings: [],
        dailyTotals: dailyTotals
    )
}

#Preview("Value · loaded") {
    ValueView(planCosts: previewPlanCosts([.claudeCode: 200, .codex: 20]))
        .environmentObject(previewVM([
            previewSnapshot(.claudeCode, name: "Claude Code",
                            month: TokenUsage(inputTokens: 82_000_000, outputTokens: 9_400_000, confidence: .exact),
                            lifetime: TokenUsage(inputTokens: 940_000_000, outputTokens: 88_000_000, confidence: .exact)),
            previewSnapshot(.codex, name: "Codex",
                            month: TokenUsage(inputTokens: 14_000_000, outputTokens: 2_100_000, confidence: .localParsed),
                            lifetime: TokenUsage(inputTokens: 120_000_000, confidence: .localParsed)),
            previewSnapshot(.cursor, name: "Cursor"),
        ]))
        .frame(width: 980, height: 700)
        .background(PadzyTheme.ground)
}

#Preview("Value · narrow 640") {
    ValueView(planCosts: previewPlanCosts([.claudeCode: 200, .codex: 20]))
        .environmentObject(previewVM([
            previewSnapshot(.claudeCode, name: "Claude Code",
                            month: TokenUsage(inputTokens: 82_000_000, outputTokens: 9_400_000, confidence: .exact),
                            lifetime: TokenUsage(inputTokens: 940_000_000, confidence: .exact)),
            previewSnapshot(.codex, name: "Codex",
                            month: TokenUsage(inputTokens: 14_000_000, confidence: .localParsed)),
        ]))
        .frame(width: 410, height: 700)
        .background(PadzyTheme.ground)
}

#Preview("Value · no plan costs") {
    ValueView(planCosts: previewPlanCosts([:]))
        .environmentObject(previewVM([
            previewSnapshot(.claudeCode, name: "Claude Code",
                            month: TokenUsage(inputTokens: 82_000_000, confidence: .exact),
                            dailyTotals: [Calendar.current.startOfDay(for: Date()): 4_200_000]),
        ]))
        .frame(width: 820, height: 620)
        .background(PadzyTheme.ground)
}

#Preview("Value · no agents") {
    ValueView(planCosts: previewPlanCosts([:]))
        .environmentObject(previewVM([]))
        .frame(width: 820, height: 520)
        .background(PadzyTheme.ground)
}
