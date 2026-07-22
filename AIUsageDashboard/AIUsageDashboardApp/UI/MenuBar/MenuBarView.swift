import SwiftUI
import AIUsageDashboardCore

/// Menu-bar popover (WP-5 rebuild to the "Tokei Dashboard" mockup, outline
/// L566-606): one cohesive panel — TOKENS·TODAY hero with Δ, a plan-value +
/// tightest-quota summary, the three busiest agents, and the two primary actions
/// (Open Tokei / Quit). Dense tier, all real published snapshot/scorecard state,
/// honest "—" whenever a baseline is missing. The compact status-bar label
/// (`MenuBarLabel`) and `MaxxerMath` are untouched (Round-2 contract).
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Closes the `MenuBarExtra(.window)` popover before any action that moves
    /// focus elsewhere (open dashboard, quit). `@Environment(\.dismiss)` alone is
    /// unreliable for menu-bar panels across macOS versions, so ALSO locate the
    /// panel in `NSApp.windows` and order it out directly. Matched by class name
    /// ("MenuBarExtraWindow" panel) — never the status-item window
    /// (NSStatusBarWindow) or the dashboard window, so a wrong match can't nuke
    /// the menu-bar item itself.
    private func dismissPopover() {
        dismiss()
        for window in NSApp.windows where window.isVisible {
            if window.identifier?.rawValue == "dashboard-window" { continue }
            let className = String(describing: type(of: window))
            if className.contains("MenuBarExtra") {
                window.close()
            }
        }
    }

    // MARK: Derived state

    /// Visible + available providers with a snapshot, in canonical order.
    private var activeSnapshots: [ProviderSnapshot] {
        ProviderID.allCases.compactMap { providerID -> ProviderSnapshot? in
            guard !ProviderVisibility.isHidden(providerID),
                  viewModel.isAvailable(providerID),
                  let snapshot = viewModel.snapshot(for: providerID) else { return nil }
            return snapshot
        }
    }

    /// Plan-value scorecard over the visible providers (same engine as the Value
    /// tab). Reads plan costs from `.standard` like every other surface.
    private var scorecard: MaxxerScorecard {
        MaxxerValueEngine.scorecard(
            snapshots: activeSnapshots,
            planCosts: MaxxerPlanCostStore(),
            now: Date()
        )
    }

    /// The constraining live window across every provider — the tightest-quota row.
    private var tightest: Utilization? {
        MaxxerMath.tightestWindow(in: viewModel.utilization)
    }

    private func providerName(_ id: ProviderID) -> String {
        viewModel.snapshot(for: id)?.displayName
            ?? id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// What the per-agent mini-list shows — flipped by the segmented control so the
    /// user can glance at either today's tokens or each agent's tightest quota.
    private enum AgentMetric: String, CaseIterable { case tokens = "Tokens", quota = "Quota" }
    @State private var agentMetric: AgentMetric = .tokens

    /// The agent's tightest live-quota window %, or `nil` when it exposes none.
    private func tightestPercent(_ id: ProviderID) -> Double? {
        viewModel.utilization.filter { $0.providerID == id }.map(\.usedPercent).max()
    }

    /// Three agents for the mini-list, ranked by whichever metric is showing:
    /// today's tokens, or how full their tightest quota is.
    private var displayedAgents: [ProviderSnapshot] {
        switch agentMetric {
        case .tokens:
            return Array(activeSnapshots
                .sorted { ($0.todayUsage.totalTokens ?? 0) > ($1.todayUsage.totalTokens ?? 0) }
                .prefix(3))
        case .quota:
            return Array(activeSnapshots
                .filter { tightestPercent($0.providerID) != nil }
                .sorted { (tightestPercent($0.providerID) ?? 0) > (tightestPercent($1.providerID) ?? 0) }
                .prefix(3))
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                stateSection {
                    SurfaceStateView(
                        kind: .error(headline: "Sync failed", detail: errorMessage),
                        compact: true,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
                footer
            } else if activeSnapshots.isEmpty && viewModel.isLoading {
                stateSection {
                    SurfaceStateView(kind: .loading(message: "Syncing"), compact: true)
                }
                footer
            } else if activeSnapshots.isEmpty {
                stateSection {
                    SurfaceStateView(
                        kind: .empty(
                            headline: "No active agents",
                            hint: "Run an AI coding agent, then it shows up here."
                        ),
                        compact: true
                    )
                }
                footer
            } else {
                hero
                HairlineDivider()
                summary
                HairlineDivider()
                metricToggle
                agents
                HairlineDivider()
                footer
            }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.window, style: .continuous)
                .fill(PadzyTheme.menuPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.window, style: .continuous)
                .stroke(PadzyTheme.border2, lineWidth: 1)
        )
        .padding(10)
        .background(PadzyTheme.ground)
        .preferredColorScheme(.dark)
        .task {
            viewModel.beginAutoSync()
            if viewModel.lastSyncedAt == nil {
                await viewModel.refresh()
            }
        }
        // Reload the previous-period pace baselines after each sync (and on open).
        .task(id: viewModel.lastSyncedAt) {
            await loadPaceBaselines()
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TOKENS · TODAY")
                    .font(.mono(size: 9.5))
                    .tracking(9.5 * 0.14)
                    .foregroundColor(PadzyTheme.ink5)
                Spacer(minLength: 8)
                if let delta = viewModel.overviewDelta {
                    DeltaLabel(delta: delta)
                } else {
                    Text("—")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ink3)
                }
            }

            Text(TokenFormatter.format(viewModel.menuBarTodayTotal))
                .font(.mono(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: Summary (plan value + tightest quota)

    private var summary: some View {
        // Build the scorecard once per render — reading the computed var twice
        // would run the whole value engine twice for one row.
        let card = scorecard
        return VStack(spacing: 11) {
            HStack {
                Text("Plan value")
                    .font(.sans(size: 12.5))
                    .foregroundColor(PadzyTheme.ink3)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(MaxxerMath.formatMultiple(card.totalValueMultiple))
                        .font(.mono(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                    if let tier = card.tier {
                        Text(tier.displayName)
                            .font(.mono(size: 9))
                            .tracking(9 * 0.06)
                            .foregroundColor(PadzyTheme.ink3)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                                    .stroke(PadzyTheme.border2, lineWidth: 1)
                            )
                    }
                }
            }

            HStack {
                Text("Tightest quota")
                    .font(.sans(size: 12.5))
                    .foregroundColor(PadzyTheme.ink3)
                Spacer(minLength: 8)
                if let tightest {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PadzyTheme.quotaColor(tightest.usedPercent))
                            .frame(width: 6, height: 6)
                        Text("\(Int(tightest.usedPercent.rounded()))%")
                            .font(.mono(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(PadzyTheme.ink)
                        Text(providerName(tightest.providerID))
                            .font(.sans(size: 11))
                            .foregroundColor(PadzyTheme.ink4)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Text("—")
                        .font(.mono(size: 13))
                        .foregroundColor(PadzyTheme.ink3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Metric toggle + top agents

    /// Segmented Tokens / Quota control — swaps what the mini-list ranks and shows,
    /// so agent quotas are one glance away without opening the app.
    private var metricToggle: some View {
        HStack(spacing: 2) {
            ForEach(AgentMetric.allCases, id: \.self) { metric in
                Button {
                    withAnimation(reduceMotion ? nil : PadzyMotion.quick) { agentMetric = metric }
                } label: {
                    Text(metric.rawValue)
                        .font(.mono(size: 10))
                        .tracking(0.4)
                        .foregroundColor(agentMetric == metric ? PadzyTheme.ink : PadzyTheme.ink4)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: PadzyRadius.chip, style: .continuous)
                                .fill(agentMetric == metric ? PadzyTheme.border2 : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(metric.rawValue.lowercased())")
                .accessibilityAddTraits(agentMetric == metric ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var agents: some View {
        VStack(spacing: 0) {
            ForEach(displayedAgents, id: \.id) { snapshot in
                Group {
                    switch agentMetric {
                    case .tokens: tokenRow(snapshot)
                    case .quota: quotaRow(snapshot)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
        .padding(8)
    }

    private func tokenRow(_ snapshot: ProviderSnapshot) -> some View {
        HStack(spacing: 9) {
            ProviderBrandMark.tinted(snapshot.providerID, size: 18)
            Text(snapshot.displayName)
                .font(.sans(size: 12.5))
                .foregroundColor(PadzyTheme.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(TokenFormatter.format(snapshot.todayUsage.totalTokens))
                .font(.mono(size: 12.5))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.displayName), \(TokenFormatter.format(snapshot.todayUsage.totalTokens)) tokens today")
    }

    /// Quota mode: glyph + a threshold-coloured fill bar + reset countdown — no
    /// name or number, the bar itself is the reading (user request). The fill is
    /// the agent's identity colour until it gets tight: bright orange at ≥80%,
    /// red at ≥90%. The fill animates 0→value on switch, and a red pace notch marks
    /// where this window stood one period ago (from the quota series) so the user
    /// reads ahead/behind vs last time — no notch when there is no prior baseline.
    private func quotaRow(_ snapshot: ProviderSnapshot) -> some View {
        let util = tightestUtil(snapshot.providerID)
        let pct = util?.usedPercent ?? 0
        return HStack(spacing: 10) {
            ProviderBrandMark.tinted(snapshot.providerID, size: 18)
            MenuQuotaBar(
                pct: pct,
                fillColor: quotaBarColor(pct, tint: AgentTint.color(snapshot.providerID)),
                baseline: baseline(for: util),
                reduceMotion: reduceMotion
            )
            .frame(maxWidth: .infinity)
            Text(resetText(util?.resetAt))
                .font(.mono(size: 10.5))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink4)
                .frame(width: 66, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quotaRowAccessibilityLabel(snapshot, util: util, pct: pct))
    }

    private func quotaRowAccessibilityLabel(_ snapshot: ProviderSnapshot, util: Utilization?, pct: Double) -> String {
        let base = "\(snapshot.displayName), tightest quota \(Int(pct.rounded())) percent, resets in \(resetText(util?.resetAt))"
        guard let prior = baseline(for: util) else { return base }
        let delta = pct - prior
        let direction = abs(delta) < 1 ? "about the same as" : (delta > 0 ? "ahead of" : "behind")
        return base + ", \(direction) last period at \(Int(prior.rounded())) percent"
    }

    private func quotaBarColor(_ pct: Double, tint: Color) -> Color {
        if pct >= 90 { return PadzyTheme.danger }
        if pct >= 80 { return Color(hex: "F5872E") }
        return tint
    }

    /// The previous-period used% for a window (nil = no baseline → no notch). Keyed
    /// by provider+window from the async series load in `loadPaceBaselines`.
    private func baseline(for util: Utilization?) -> Double? {
        guard let util else { return nil }
        return paceBaselines["\(util.providerID.rawValue)_\(util.window.rawValue)"]
    }

    /// Previous-period used% per provider+window, loaded from the persisted quota
    /// series. Empty until the first load; a provider stays absent (→ no notch) when
    /// the series does not reach back ~one window ago, so a fresh install never shows
    /// a fabricated baseline.
    @State private var paceBaselines: [String: Double] = [:]

    /// For each displayed provider's tightest window, find the sample nearest to one
    /// window-duration ago (the "same point last period"). Requires the sample land
    /// within ±half a window of that instant, else there is no honest baseline.
    private func loadPaceBaselines() async {
        var result: [String: Double] = [:]
        let referenceNow = Date()
        for snapshot in activeSnapshots {
            guard let util = tightestUtil(snapshot.providerID),
                  let duration = MaxxerMath.canonicalWindowDuration(for: util.window) else { continue }
            let target = referenceNow.addingTimeInterval(-duration)
            let samples = await QuotaSeriesStore.shared.samples(for: util.providerID, windowType: util.window)
            let nearest = samples.min {
                abs($0.sampledAt.timeIntervalSince(target)) < abs($1.sampledAt.timeIntervalSince(target))
            }
            if let nearest, abs(nearest.sampledAt.timeIntervalSince(target)) <= duration / 2 {
                result["\(util.providerID.rawValue)_\(util.window.rawValue)"] = nearest.usedPercent
            }
        }
        paceBaselines = result
    }

    private func tightestUtil(_ id: ProviderID) -> Utilization? {
        viewModel.utilization.filter { $0.providerID == id }.max { $0.usedPercent < $1.usedPercent }
    }

    /// Compact reset countdown ("4d 9h" / "2h 41m" / "41m") — no ticking seconds,
    /// so a static popover render doesn't read as a frozen clock.
    private func resetText(_ resetAt: Date?) -> String {
        guard let resetAt else { return "—" }
        let seconds = Int(resetAt.timeIntervalSince(Date()))
        guard seconds > 0 else { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: {
                dismissPopover()
                openWindow(id: "dashboard-window")
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Text("Open Tokei")
                    .font(.sans(size: 12.5, weight: .semibold))
                    .foregroundColor(PadzyTheme.ground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                            .fill(PadzyTheme.accent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                dismissPopover()
                NSApp.terminate(nil)
            }) {
                Text("Quit ⌘Q")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink4)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .accessibilityLabel("Quit Tokei")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Building blocks

    private func stateSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
}

/// The menu-bar quota fill bar: a muted track with a threshold-coloured fill that
/// animates 0→value on appear (final state only under Reduce Motion), plus an
/// optional red pace notch marking where this window stood one period ago. The notch
/// is 10pt tall over the 6pt track so its nubs stay visible even when they sit over
/// the fill, and it never renders when there is no prior baseline.
private struct MenuQuotaBar: View {
    let pct: Double
    let fillColor: Color
    /// Previous-period used% (0…100); `nil` = no baseline → no notch.
    let baseline: Double?
    let reduceMotion: Bool

    @State private var filled = false

    var body: some View {
        let clamped = max(0, min(100, pct))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(PadzyTheme.muted.opacity(0.25))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fillColor)
                    .frame(width: geo.size.width * CGFloat(clamped / 100.0) * (filled ? 1 : 0), height: 6)
                if let baseline {
                    let x = geo.size.width * CGFloat(max(0, min(100, baseline)) / 100.0)
                    Rectangle()
                        .fill(PadzyTheme.danger)
                        .frame(width: 2, height: 10)
                        .offset(x: min(max(0, x - 1), geo.size.width - 2))
                        .help("Last period: \(Int(baseline.rounded()))%")
                        .accessibilityHidden(true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
        .onAppear {
            if reduceMotion { filled = true }
            else { withAnimation(PadzyMotion.settle) { filled = true } }
        }
    }
}

// MARK: - Previews

@MainActor
private func popoverVM() -> DashboardViewModel {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let vm = DashboardViewModel()
    vm.lastSyncedAt = Date()
    let today = DateHelpers.startOfToday()
    let calendar = Calendar.current
    var totals: [Date: Int] = [:]
    let values = [4_200_000, 9_800_000, 7_400_000, 15_200_000, 11_100_000, 18_600_000, 12_500_000]
    for (i, v) in values.enumerated() {
        if let day = calendar.date(byAdding: .day, value: -(values.count - 1 - i), to: today) {
            totals[day] = v
        }
    }
    vm.snapshots = [
        ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 71, limit: 100,
                                       resetAt: Date().addingTimeInterval(4 * 86_400),
                                       confidence: .providerReported, source: "preview")],
            todayUsage: TokenUsage(inputTokens: 9_000_000, outputTokens: 3_500_000, confidence: .exact),
            weekUsage: .unavailable,
            dailyTotals: totals
        ),
        ProviderSnapshot(
            providerID: .codex, displayName: "Codex", authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .codex, type: .session, used: 41, limit: 100,
                                       resetAt: Date().addingTimeInterval(3 * 3600),
                                       confidence: .providerReported, source: "preview")],
            todayUsage: TokenUsage(inputTokens: 2_400_000, outputTokens: 800_000, confidence: .localParsed),
            weekUsage: .unavailable
        ),
        ProviderSnapshot(
            providerID: .cursor, displayName: "Cursor", authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 1_100_000, confidence: .localParsed),
            weekUsage: .unavailable,
            warnings: [ProviderWarning(message: "Plan: Pro", level: .info)]
        ),
    ]
    return vm
}

#Preview("Popover · live") {
    MenuBarView().environmentObject(popoverVM())
}

#Preview("Popover · empty") {
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let vm = DashboardViewModel()
    return MenuBarView().environmentObject(vm)
}
