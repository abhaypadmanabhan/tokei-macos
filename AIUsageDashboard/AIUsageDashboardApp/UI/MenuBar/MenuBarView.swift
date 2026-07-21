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

    /// The three busiest agents today — the mockup's mini-list.
    private var topAgents: [ProviderSnapshot] {
        activeSnapshots
            .sorted { ($0.todayUsage.totalTokens ?? 0) > ($1.todayUsage.totalTokens ?? 0) }
            .prefix(3)
            .map { $0 }
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
        VStack(spacing: 11) {
            HStack {
                Text("Plan value")
                    .font(.sans(size: 12.5))
                    .foregroundColor(PadzyTheme.ink3)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(MaxxerMath.formatMultiple(scorecard.totalValueMultiple))
                        .font(.mono(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                    if let tier = scorecard.tier {
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

    // MARK: Top agents

    private var agents: some View {
        VStack(spacing: 0) {
            ForEach(topAgents, id: \.id) { snapshot in
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
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(snapshot.displayName), \(TokenFormatter.format(snapshot.todayUsage.totalTokens)) tokens today")
            }
        }
        .padding(8)
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
