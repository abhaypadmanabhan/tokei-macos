import SwiftUI
import AIUsageDashboardCore

/// The value surface (#23 UI half + #41): what your paid plans are actually
/// worth against what the same month of tokens would cost at public API rates.
///
/// Reads the frozen Maxxer contract (Bible §4) through
/// `MaxxerValueEngine.scorecard(snapshots:planCosts:now:)` and the existing
/// `ProviderSnapshot.lifetimeUsage` API — no Core edits. Until WP-1 merges, that
/// entry point resolves to `MaxxerContractShim.swift`; the call site here is
/// written against the frozen signature and does not change at integration.
///
/// Editorial contract: dollar figures are `ink` (they are data, not state), the
/// single accent is spent only on the tier chip's active tick and the empty
/// state's primary action, and every unknown renders `—` rather than a
/// confident zero. No animation on this surface, so Reduce Motion has nothing
/// to suppress.
struct ValueView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Routes to the Settings pane, where the plan-cost fields live.
    var onOpenPlanCosts: () -> Void = {}

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
        VStack(alignment: .leading, spacing: 0) {
            header
            HairlineDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            storeRevision &+= 1
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Value")
                headline
            }
            Spacer(minLength: 12)
            if hasAnyPlanCost, let tier = scorecard.tier {
                TierChip(tier: tier)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// "3.4× PLAN VALUE" — or an honest degradation when the multiple can't be
    /// computed, which is a different sentence from a small multiple.
    private var headline: some View {
        let multiple = scorecard.totalValueMultiple
        return Text(multiple == nil ? "— PLAN VALUE" : "\(MaxxerMath.formatMultiple(multiple)) PLAN VALUE")
            .font(.mono(size: 18))
            .monospacedDigit()
            .foregroundColor(multiple == nil ? PadzyTheme.muted : PadzyTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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

    /// The surface's real empty state: agents are connected, but Tokei has no
    /// idea what the user pays, so every multiple would be `—`. Leads with the
    /// action that fixes it.
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

    private var loadedState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                valueTableCard
                lifetimeCard
            }
            .padding(20)
        }
    }

    // MARK: Value table (Dense tier)

    private var valueTableCard: some View {
        SectionCard("Value by agent", trailing: {
            Text("MONTH TO DATE")
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
        }) {
            VStack(spacing: 0) {
                ValueTableHeader()
                HairlineDivider()

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ValueProviderRow(value: row.value, displayName: row.displayName, providerID: row.providerID)
                    if index < rows.count - 1 {
                        HairlineDivider()
                    }
                }

                HairlineDivider()
                ValueTotalRow(scorecard: scorecard)
            }

            // The total multiple divides EVERY priced agent's API-equivalent spend by
            // only the plans the user has actually costed (Bible §4 / WP-1 AC: an
            // unconfigured plan is excluded from `totalPlanUSD` but its usage still
            // counts toward `totalAPIEquivalentUSD`). That inflates the headline, so
            // say so rather than letting a big number speak for itself.
            if hasUnpricedPlans {
                Text("\(unpricedNames) \(unpricedCount == 1 ? "has" : "have") usage but no plan cost set, so the total multiple weighs their spend against only the plans you've priced. Add the missing prices for a true figure.")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if scorecard.providers.contains(where: { $0.confidence == .unavailable }) {
                Text("Agents with no month-to-date token data are listed but excluded from the totals — they are unmeasured, not zero.")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Agents whose usage is priced into the API-equivalent total but whose plan
    /// cost the user has not entered — the reason the total multiple reads high.
    private var unpricedRows: [Row] {
        rows.filter { $0.value.apiEquivalentUSD != nil && $0.value.planMonthlyUSD == nil }
    }

    private var hasUnpricedPlans: Bool { !unpricedRows.isEmpty }

    private var unpricedCount: Int { unpricedRows.count }

    private var unpricedNames: String {
        let names = unpricedRows.map(\.displayName)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and \(names[names.count - 1])"
        }
    }

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

    // MARK: Lifetime (#41)

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
    /// frozen §4 contract carries no presentation strings, and this extension
    /// survives WP-1 integration unchanged.
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
}

/// Tier chip: leading 2px accent tick (the Padzy active-state mark — tier IS the
/// surface's live state) with an ink label on a hairline-bounded surface. The
/// tier is never signalled by colour alone; the word carries the meaning.
struct TierChip: View {
    let tier: MaxxerTier

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(PadzyTheme.accent)
                .frame(width: 2)
            Text(tier.displayName)
                .font(.display(size: 12, weight: .bold))
                .foregroundColor(PadzyTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.3), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tier: \(tier.displayName). \(tier.blurb)")
    }
}

// MARK: - Dense table rows

/// Shared column widths so the header, every provider row, and the total row
/// line up on one grid.
private enum ValueColumn {
    static let plan: CGFloat = 68
    static let apiEquivalent: CGFloat = 82
    static let multiple: CGFloat = 52
    static let spacing: CGFloat = 10
}

private struct ValueTableHeader: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ValueColumn.spacing) {
                label("Agent", width: nil, alignment: .leading)
                label("Plan", width: ValueColumn.plan, alignment: .trailing)
                label("API equiv", width: ValueColumn.apiEquivalent, alignment: .trailing)
                label("Value", width: ValueColumn.multiple, alignment: .trailing)
            }
            HStack(spacing: ValueColumn.spacing) {
                label("Agent", width: nil, alignment: .leading)
                label("Value", width: ValueColumn.multiple, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    private func label(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(text.uppercased())
            .font(.mono(size: 9))
            .tracking(9 * 0.08)
            .foregroundColor(PadzyTheme.muted)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// One agent's value row. Wide layout is the full five-column grid; below that
/// the dollar detail wraps to a second line rather than truncating, so the
/// 640pt minimum window still shows real numbers.
private struct ValueProviderRow: View {
    let value: MaxxerProviderValue
    let displayName: String
    let providerID: ProviderID?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wide
            narrow
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var wide: some View {
        HStack(spacing: ValueColumn.spacing) {
            agentCell
            amount(MaxxerMath.formatUSD(value.planMonthlyUSD), width: ValueColumn.plan)
            amount(MaxxerMath.formatUSD(value.apiEquivalentUSD), width: ValueColumn.apiEquivalent)
            multipleCell
            ConfidenceBadge(confidence: value.confidence, compact: true)
        }
    }

    private var narrow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: ValueColumn.spacing) {
                agentCell
                multipleCell
            }
            HStack(spacing: 8) {
                Text("PLAN \(MaxxerMath.formatUSD(value.planMonthlyUSD))  ·  API \(MaxxerMath.formatUSD(value.apiEquivalentUSD))")
                    .font(.mono(size: 10))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                ConfidenceBadge(confidence: value.confidence, compact: true)
            }
        }
    }

    private var agentCell: some View {
        HStack(spacing: 8) {
            if let providerID {
                ProviderMark(providerID, size: 14)
                    .frame(width: 18, height: 18)
            }
            Text(displayName.uppercased())
                .font(.display(size: 11, weight: .bold))
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The multiple is the row's headline number, so it keeps ink weight even
    /// when unknown-dashed; the dollar columns stay ink too (data, not state).
    private var multipleCell: some View {
        Text(MaxxerMath.formatMultiple(value.valueMultiple))
            .font(.mono(size: 13))
            .monospacedDigit()
            .foregroundColor(value.valueMultiple == nil ? PadzyTheme.muted : PadzyTheme.ink)
            .lineLimit(1)
            .frame(width: ValueColumn.multiple, alignment: .trailing)
    }

    private func amount(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.mono(size: 11))
            .monospacedDigit()
            .foregroundColor(text == MaxxerMath.unknownPlaceholder ? PadzyTheme.muted : PadzyTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: .trailing)
    }

    private var accessibilityText: String {
        let plan = value.planMonthlyUSD == nil ? "no plan cost set" : "plan \(MaxxerMath.formatUSD(value.planMonthlyUSD))"
        let api = value.apiEquivalentUSD == nil ? "API equivalent unavailable" : "API equivalent \(MaxxerMath.formatUSD(value.apiEquivalentUSD))"
        let multiple = value.valueMultiple == nil ? "value multiple unavailable" : "\(MaxxerMath.formatMultiple(value.valueMultiple)) plan value"
        return "\(displayName): \(plan), \(api), \(multiple). Confidence \(value.confidence.displayName)."
    }
}

private struct ValueTotalRow: View {
    let scorecard: MaxxerScorecard

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wide
            narrow
        }
        .padding(.vertical, 9)
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
            amount(MaxxerMath.formatUSD(scorecard.totalPlanUSD), width: ValueColumn.plan)
            amount(MaxxerMath.formatUSD(scorecard.totalAPIEquivalentUSD), width: ValueColumn.apiEquivalent)
            multipleCell
            // Keeps the total row's trailing edge on the same grid as the rows
            // above it, which each end in a confidence badge.
            ConfidenceBadge(confidence: .estimated, compact: true).hidden()
        }
    }

    private var narrow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: ValueColumn.spacing) {
                totalLabel
                multipleCell
            }
            Text("PLAN \(MaxxerMath.formatUSD(scorecard.totalPlanUSD))  ·  API \(MaxxerMath.formatUSD(scorecard.totalAPIEquivalentUSD))")
                .font(.mono(size: 10))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var totalLabel: some View {
        Text("TOTAL")
            .font(.mono(size: 10))
            .tracking(10 * 0.08)
            .foregroundColor(PadzyTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var multipleCell: some View {
        Text(MaxxerMath.formatMultiple(scorecard.totalValueMultiple))
            .font(.mono(size: 14))
            .monospacedDigit()
            .foregroundColor(scorecard.totalValueMultiple == nil ? PadzyTheme.muted : PadzyTheme.ink)
            .lineLimit(1)
            .frame(width: ValueColumn.multiple, alignment: .trailing)
    }

    private func amount(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.mono(size: 11))
            .monospacedDigit()
            .foregroundColor(text == MaxxerMath.unknownPlaceholder ? PadzyTheme.muted : PadzyTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: .trailing)
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
