import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False when the app is idling in the menu bar; stops the status-dot pulse so
    /// its `repeatForever` animation isn't left churning on the retained window.
    @Environment(\.dashboardVisible) private var dashboardVisible

    /// Local top-level navigation. `Core` is untouched; `.settings` is mirrored
    /// into `viewModel.showingSettings` so existing Core consumers stay in sync.
    @State private var section: AppSection = .overview

    /// The tab the content returns to when a drill-in is dismissed, and the pane
    /// that stays rendered underneath one. Only ever written by a tab selection,
    /// so drilling in and backing out is a round trip.
    @State private var homeTab: DashboardTab = .overview

    /// Drives the `+` add-agent sheet, shared by Overview's blank-canvas call to
    /// action and the Settings pane.
    @State private var showingAddAgent = false

    /// First non-hidden provider in chip-strip order — the chip that down-arrow
    /// from a tab drills into, and the one left-arrow stops at.
    private var firstVisibleProvider: ProviderID? {
        ProviderID.allCases.first { !ProviderVisibility.isHidden($0) }
    }

    /// Advances selection, skipping hidden providers. Bounded by the provider
    /// count so an all-hidden state can never loop forever.
    private func selectNextVisible() {
        for _ in ProviderID.allCases {
            viewModel.selectNextProvider()
            if !ProviderVisibility.isHidden(viewModel.selectedProvider) { break }
        }
    }

    private func selectPreviousVisible() {
        for _ in ProviderID.allCases {
            viewModel.selectPreviousProvider()
            if !ProviderVisibility.isHidden(viewModel.selectedProvider) { break }
        }
    }

    var body: some View {
        ZStack {
            if dashboardVisible {
                shell

                // Settings drawer — driven directly by `viewModel.showingSettings`
                // (the gear toggles it; the menu-bar Settings action sets it true).
                if viewModel.showingSettings {
                    SettingsDrawer(
                        onClose: { viewModel.showingSettings = false },
                        onOpenAgents: { select(tab: .agents) }
                    )
                    .zIndex(1)
                }

                // Add-agent drawer — driven by the shell's `showingAddAgent` flag,
                // shared by Overview's blank canvas and the Agents tab's + button.
                if showingAddAgent {
                    AddAgentDrawer(onClose: { showingAddAgent = false })
                        .zIndex(1)
                }
            } else {
                // Idling in the menu bar. The dashboard is a retained `Window` scene,
                // so its whole graph — charts, status strip, relative-time labels —
                // keeps re-rendering off screen and burns CPU for nothing. Collapse to
                // a static fill while hidden; the shell rebuilds the moment it's shown.
                PadzyTheme.ground
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .preferredColorScheme(.dark)
        // Slide/fade the drawers in and out; static under Reduce Motion.
        .animation(reduceMotion ? nil : PadzyMotion.quick, value: viewModel.showingSettings)
        .animation(reduceMotion ? nil : PadzyMotion.quick, value: showingAddAgent)
    }

    /// The dashboard shell — tab bar, ambient quota banner, routed content, and the
    /// status strip. The Settings and Add-agent drawers overlay this in `body`.
    private var shell: some View {
        VStack(spacing: 0) {
            DashboardTabBar(
                activeTab: section.tab,
                isSettingsActive: viewModel.showingSettings,
                showsRangeSelector: section.usesTimeRange,
                range: $viewModel.range,
                onSelect: { select(tab: $0) },
                onOpenSettings: { viewModel.showingSettings.toggle() }
            )

            // Ambient quota strip: only on a non-drill-in, non-Agents tab, and only
            // when a live window actually exists (the banner carries its own top
            // hairline; the divider below closes the strip and rules off the content).
            if !section.isDrillIn, section.tab != .agents, let tightest = tightestUtilization {
                PressureBanner(
                    utilization: tightest,
                    providerDisplayName: providerDisplayName(for: tightest.providerID),
                    onTap: { openProvider($0) }
                )
            }
            HairlineDivider()

            content
            DashboardStatusStrip()
        }
        .background(PadzyTheme.ground)
        .focusable()
        // Arrow semantics: horizontal moves along the current run — the tab strip on
        // a tab, or between providers while drilled into one. Down enters the first
        // provider's detail from a tab (the drill-in the mockup's agent grid will own
        // later); up leaves any drill-in for the tab that owns the content behind it.
        .onMoveCommand { direction in
            switch direction {
            case .left:
                if case .provider = section {
                    selectPreviousVisible()
                    openProvider(viewModel.selectedProvider)
                } else if let tab = section.tab, let previous = tab.previous {
                    select(tab: previous)
                }
            case .right:
                if case .provider = section {
                    selectNextVisible()
                    openProvider(viewModel.selectedProvider)
                } else if let tab = section.tab, let next = tab.next {
                    select(tab: next)
                }
            case .down:
                // From a tab, drop into the first provider's detail.
                if section.tab != nil, let first = firstVisibleProvider {
                    openProvider(first)
                }
            case .up:
                if section.isDrillIn { goBack() }
            @unknown default:
                break
            }
        }
        .onAppear {
            // Seed the canvas once so a brand-new user (no agents on disk) leads with
            // the + instead of a wall of empty provider rows; idempotent thereafter.
            AddAgentModel.seedOnFirstLaunchIfNeeded()
        }
        .task {
            viewModel.beginAutoSync()
            await viewModel.refresh()
        }
    }

    // MARK: Navigation

    /// The single tightest live window across providers — drives the ambient
    /// pressure banner. `nil` when no provider reports a live quota anywhere.
    private var tightestUtilization: Utilization? {
        MaxxerMath.tightestWindow(in: viewModel.utilization)
    }

    /// Resolved provider name for the banner (falls back to a de-underscored id).
    private func providerDisplayName(for providerID: ProviderID) -> String {
        viewModel.snapshot(for: providerID)?.displayName
            ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private func select(tab: DashboardTab) {
        homeTab = tab
        navigate(to: tab.section)
        viewModel.showingSettings = false
    }

    private func openProvider(_ providerID: ProviderID) {
        viewModel.selectedProvider = providerID
        navigate(to: .provider(providerID))
        viewModel.showingSettings = false
    }

    /// Opens the Settings drawer (used by the Cursor "enable online" hand-off). The
    /// gear toggles the same flag; the × / scrim / Escape clear it.
    private func openSettings() {
        viewModel.showingSettings = true
    }

    /// Dismiss any drill-in back to the tab that owns the content behind it.
    private func goBack() {
        navigate(to: homeTab.section)
        viewModel.showingSettings = false
    }

    /// Single write point for `section`, so the drill-in transition is animated
    /// in exactly one place — and skipped entirely under Reduce Motion, where the
    /// pane swap happens instantly instead of sliding.
    private func navigate(to destination: AppSection) {
        if reduceMotion {
            section = destination
        } else {
            withAnimation(.easeOut(duration: 0.18)) { section = destination }
        }
    }

    // MARK: Content

    /// The tab pane always stays mounted; a drill-in renders opaquely over it and
    /// slides away on dismiss, which is what makes the chip strip read as a
    /// selector rather than as navigation to somewhere else.
    private var content: some View {
        ZStack(alignment: .topLeading) {
            tabPane
            if section.isDrillIn {
                VStack(spacing: 0) {
                    backBar
                    HairlineDivider()
                    drillInPane
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(PadzyTheme.ground)
                .transition(
                    reduceMotion
                        ? .identity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var tabPane: some View {
        switch homeTab {
        case .overview:
            OverviewView(
                onSelectProvider: { openProvider($0) },
                onAddAgent: { showingAddAgent = true }
            )
        case .value:
            ValueView(
                onOpenPlanCosts: { openSettings() },
                onSelectProvider: { openProvider($0) }
            )
        case .agents:
            ConnectionsView(onAddAgent: { showingAddAgent = true })
        }
    }

    @ViewBuilder
    private var drillInPane: some View {
        switch section {
        case .provider:
            DashboardProviderPane(onEnableOnline: { openSettings() })
        case .overview, .value, .connections:
            EmptyView()
        }
    }

    /// Back affordance for every drill-in: an explicit button (Esc also works)
    /// plus a breadcrumb naming the tab the content will return to.
    private var backBar: some View {
        HStack(spacing: 12) {
            Button(action: { goBack() }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("BACK")
                        .font(.mono(size: 10))
                        .tracking(0.5)
                }
                .foregroundColor(PadzyTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                        .stroke(PadzyTheme.muted.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Back to \(homeTab.accessibilityName)")

            Text(breadcrumb)
                .font(.mono(size: 10))
                .tracking(0.5)
                .foregroundColor(PadzyTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var breadcrumb: String {
        let leaf: String
        switch section {
        case let .provider(providerID):
            leaf = (viewModel.snapshot(for: providerID)?.displayName ?? providerID.rawValue)
                .replacingOccurrences(of: "_", with: " ")
        case .overview, .value, .connections: leaf = ""
        }
        return "\(homeTab.accessibilityName) / \(leaf)".uppercased()
    }

}

// MARK: - Previews

@MainActor
private func previewViewModel() -> DashboardViewModel {
    // Make every provider visible so the chip strip + panes render deterministically.
    for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
    let vm = DashboardViewModel()
    vm.lastSyncedAt = Date(timeIntervalSince1970: 1_769_000_000)
    vm.snapshots = [
        ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 94, limit: 100,
                                       resetAt: Date(timeIntervalSince1970: 1_769_400_000),
                                       confidence: .providerReported, source: "preview")],
            todayUsage: TokenUsage(inputTokens: 128_000, outputTokens: 42_000,
                                   cacheReadTokens: 512_000, cacheCreationTokens: 8_000,
                                   confidence: .exact),
            weekUsage: TokenUsage(inputTokens: 900_000, outputTokens: 300_000, confidence: .exact),
            warnings: []
        ),
        ProviderSnapshot(providerID: .cursor, displayName: "Cursor", authStatus: .authenticated,
                         quotaWindows: [], todayUsage: .unavailable, weekUsage: .unavailable,
                         warnings: [ProviderWarning(message: "Plan: Pro", level: .info)]),
    ]
    vm.selectedProvider = .claudeCode
    return vm
}

#Preview("Window · small 640×480") {
    DashboardView().environmentObject(previewViewModel())
        .frame(width: 640, height: 480)
}

#Preview("Window · mid 900×640") {
    DashboardView().environmentObject(previewViewModel())
        .frame(width: 900, height: 640)
}

#Preview("Window · full 1440×900") {
    DashboardView().environmentObject(previewViewModel())
        .frame(width: 1440, height: 900)
}

#Preview("Plan-only · Antigravity") {
    UserDefaults.standard.set(true, forKey: "antigravityOnlineQuotaEnabled")
    let vm = previewViewModel()
    let reset5h = Date().addingTimeInterval(3 * 3600 + 20 * 60)
    let resetWeek = Date().addingTimeInterval(4 * 86_400 + 6 * 3600)
    vm.snapshots.append(ProviderSnapshot(
        providerID: .antigravity, displayName: "Antigravity", authStatus: .authenticated,
        quotaWindows: [
            QuotaWindow(providerID: .antigravity, type: .weekly, used: 46, limit: 100,
                        resetAt: resetWeek, confidence: .providerReported, source: "preview",
                        label: "Gemini Models", bucketKey: "ag_gemini_weekly"),
            QuotaWindow(providerID: .antigravity, type: .fiveHour, used: 12, limit: 100,
                        resetAt: reset5h, confidence: .providerReported, source: "preview",
                        label: "Gemini Models", bucketKey: "ag_gemini_5h"),
            QuotaWindow(providerID: .antigravity, type: .weekly, used: 91, limit: 100,
                        resetAt: resetWeek, confidence: .providerReported, source: "preview",
                        label: "Claude and GPT Models", bucketKey: "ag_claude_weekly"),
            QuotaWindow(providerID: .antigravity, type: .fiveHour, used: 68, limit: 100,
                        resetAt: reset5h, confidence: .providerReported, source: "preview",
                        label: "Claude and GPT Models", bucketKey: "ag_claude_5h"),
        ],
        todayUsage: .unavailable, weekUsage: .unavailable,
        warnings: [ProviderWarning(message: "Plan: Pro", level: .info)]
    ))
    vm.selectedProvider = .antigravity
    return DashboardView().environmentObject(vm)
        .frame(width: 1000, height: 800)
}

#Preview("Plan-only · Antigravity quota off/empty") {
    UserDefaults.standard.set(false, forKey: "antigravityOnlineQuotaEnabled")
    let vm = previewViewModel()
    vm.snapshots.append(ProviderSnapshot(
        providerID: .antigravity, displayName: "Antigravity", authStatus: .authenticated,
        quotaWindows: [],
        todayUsage: .unavailable, weekUsage: .unavailable,
        warnings: [ProviderWarning(message: "Plan: Pro", level: .info)]
    ))
    vm.selectedProvider = .antigravity
    return DashboardView().environmentObject(vm)
        .frame(width: 900, height: 640)
}
