import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    @State private var pulseOpacity: Double = 1.0
    @State private var countdownTick = Date()
    private let countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var isClaudeInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

    private var selectedSnapshot: ProviderSnapshot? {
        viewModel.snapshot(for: viewModel.selectedProvider)
    }

    /// The visible, quota-bearing provider with the most headroom — the lowest
    /// tightest-window used% (mirrors `OverviewView.headroomProviderID`). `nil`
    /// unless at least two providers have a live window, so "route here" always
    /// implies a real choice. Drives the drill-in's green route chip.
    private var routeTargetProviderID: ProviderID? {
        var tightestByProvider: [ProviderID: Double] = [:]
        for util in viewModel.utilization {
            if let existing = tightestByProvider[util.providerID] {
                if util.usedPercent > existing { tightestByProvider[util.providerID] = util.usedPercent }
            } else {
                tightestByProvider[util.providerID] = util.usedPercent
            }
        }
        let quotaBearing: [(id: ProviderID, pct: Double)] = ProviderID.allCases
            .filter { !ProviderVisibility.isHidden($0) }
            .compactMap { id in tightestByProvider[id].map { (id, $0) } }
        guard quotaBearing.count >= 2 else { return nil }
        return quotaBearing.min(by: { $0.pct < $1.pct })?.id
    }

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
            statusStrip
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
        .onReceive(countdownTimer) { _ in
            countdownTick = Date()
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
            providerDetailPane
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

    // MARK: 02 / USAGE

    /// True when the selected provider has any real signal to render (tokens in
    /// any window, an active quota, a cost, a plan/tier signal, or a daily-total
    /// bonus stat like Cursor's accepted lines). Drives the empty state — a
    /// provider that's merely `.planOnly` still has something honest to show.
    private var selectedHasData: Bool {
        guard let snapshot = selectedSnapshot else { return false }
        let tokenTotals = [snapshot.todayUsage.totalTokens, snapshot.weekUsage.totalTokens,
                           snapshot.monthUsage?.totalTokens, snapshot.lifetimeUsage?.totalTokens]
            .compactMap { $0 }
        if tokenTotals.contains(where: { $0 > 0 }) { return true }
        if snapshot.quotaWindows.contains(where: { $0.confidence != .unavailable }) { return true }
        if snapshot.costUsage?.amount != nil { return true }
        if ProviderMetadata.planText(from: snapshot.warnings) != nil { return true }
        if let totals = snapshot.dailyTotals, !totals.isEmpty { return true }
        return false
    }

    /// Provider-detail surface: resolves to error → tailored empty (Claude not
    /// installed) → loading → generic empty → loaded, in that precedence.
    @ViewBuilder
    private var providerDetailPane: some View {
        if let errorMessage = viewModel.errorMessage {
            SurfaceStateView(
                header: "USAGE",
                kind: .error(headline: "Sync failed", detail: errorMessage),
                onRetry: { Task { await viewModel.refresh() } }
            )
        } else if viewModel.selectedProvider == .claudeCode && !isClaudeInstalled {
            emptyState
        } else if selectedSnapshot == nil && viewModel.isLoading {
            SurfaceStateView(
                header: "USAGE",
                kind: .loading(message: "Reading local logs")
            )
        } else if !selectedHasData {
            SurfaceStateView(
                header: "USAGE",
                kind: .empty(
                    headline: "No usage data",
                    hint: "No data yet at \(ProviderMetadata.localPaths(for: viewModel.selectedProvider).joined(separator: ", ")). Run it once, then use Sync Now below."
                )
            )
        } else if let snapshot = selectedSnapshot {
            // ONE unified drill-in (WP-5 P6) for BOTH full-metrics and plan-only
            // providers — the plan-only branch now falls through here too. Analytics
            // from the frozen §4 DashboardViewModel surface; value/route/plan from
            // the Maxxer scorecard + provider metadata.
            ProviderDetailView(
                snapshot: snapshot,
                trend: viewModel.trend(for: snapshot.providerID),
                peakHour: viewModel.peakHour(for: snapshot.providerID),
                lastSyncedAt: viewModel.lastSyncedAt,
                value: MaxxerValueEngine.scorecard(
                    snapshots: viewModel.snapshots.filter { !ProviderVisibility.isHidden($0.providerID) },
                    planCosts: MaxxerPlanCostStore(),
                    now: Date()
                ).providers.first { $0.providerID == snapshot.providerID.rawValue },
                isRouteTarget: routeTargetProviderID == snapshot.providerID,
                planLabel: ProviderMetadata.planText(from: snapshot.warnings),
                onEnableOnline: { openSettings() }
            )
        } else {
            SurfaceStateView(header: "USAGE", kind: .loading(message: "Reading local logs"))
        }
    }

    // MARK: Status

    /// Bottom status bar (mockup): a live sync dot, a relative "Synced …" line, the
    /// today-usage confidence, the watched path, and a trailing "Sync now". Reflows
    /// toward the 640pt minimum by dropping the confidence first, then the path — the
    /// dot, the status line, and Sync now always stay so nothing critical clips.
    private var statusStrip: some View {
        VStack(spacing: 0) {
            // Non-info warnings ride above the bar as their own hairline-bounded
            // sub-banner (kept from the prior status strip).
            if let warnings = selectedSnapshot?.warnings.filter({ $0.level != .info }), !warnings.isEmpty {
                HairlineDivider()
                HStack(spacing: 8) {
                    Text("!!")
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.accent)
                    Text(warnings.map(\.message).joined(separator: "  ·  ").uppercased())
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.ink4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(PadzyTheme.statusBar)
            }
            HairlineDivider()
            ViewThatFits(in: .horizontal) {
                statusRow(showConfidence: true, showPath: true)
                statusRow(showConfidence: false, showPath: true)
                statusRow(showConfidence: false, showPath: false)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(PadzyTheme.statusBar)
        }
    }

    /// One status-bar layout. `showConfidence` / `showPath` are toggled by the
    /// `ViewThatFits` reflow above; the dot, the "Synced …" line, and Sync now are
    /// always present. The path is the flexible, middle-truncating segment.
    private func statusRow(showConfidence: Bool, showPath: Bool) -> some View {
        HStack(spacing: 10) {
            statusDot

            Text(syncStatusText)
                .font(.sans(size: 11.5))
                .foregroundColor(PadzyTheme.ink3)
                .lineLimit(1)
                .fixedSize()

            if showConfidence, let confidence = confidenceLabel {
                Text(confidence)
                    .font(.sans(size: 11.5))
                    .foregroundColor(PadzyTheme.ink4)
                    .lineLimit(1)
                    .fixedSize()
            }

            if showPath, let path = watchedPath {
                Text(path)
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink5)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            syncButton
        }
    }

    /// 6px status dot: warn + pulsing while a sync is in flight, else a steady good.
    /// The pulse is gated on Reduce Motion (static full opacity when it is set).
    private var statusDot: some View {
        Circle()
            .fill(viewModel.isLoading ? PadzyTheme.warn : PadzyTheme.good)
            .frame(width: 6, height: 6)
            .opacity(viewModel.isLoading ? pulseOpacity : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.2
                }
            }
            .accessibilityHidden(true)
    }

    private var syncButton: some View {
        Button(action: { Task { await viewModel.refresh() } }) {
            Text("Sync now")
                .font(.sans(size: 11.5, weight: .semibold))
                .foregroundColor(viewModel.isLoading ? PadzyTheme.ink5 : PadzyTheme.accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Sync now")
    }

    /// "Syncing…" while a refresh is in flight, else "Synced <relative>" (or a
    /// first-run "Not synced yet").
    private var syncStatusText: String {
        if viewModel.isLoading { return "Syncing…" }
        guard let syncedRelative else { return "Not synced yet" }
        return "Synced \(syncedRelative)"
    }

    /// Relative age of the last sync — "just now", "3m ago", "2h ago", "1d ago".
    /// `nil` before the first sync. Recomputed each second via `countdownTick`.
    private var syncedRelative: String? {
        _ = countdownTick
        guard let last = viewModel.lastSyncedAt else { return nil }
        let seconds = max(0, Int(Date().timeIntervalSince(last)))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Today-usage confidence for the selected provider, sentence-case (subtle, per
    /// the mockup — no shouting REPORTED/ESTIMATED chip on this surface).
    private var confidenceLabel: String? {
        selectedSnapshot?.todayUsage.confidence.displayName
    }

    /// The first local path Tokei watches for the selected provider.
    private var watchedPath: String? {
        ProviderMetadata.localPaths(for: viewModel.selectedProvider).first
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Usage")
            Text("NO CLAUDE CODE DIRECTORY DETECTED")
                .font(.display(size: 18, weight: .black))
                .foregroundColor(PadzyTheme.ink)
            Text("Expected location: ~/.claude")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.ink)
            Text("Install Claude Code and run it once in your terminal to initialize session logs.")
                .font(.system(size: 12))
                .foregroundColor(PadzyTheme.muted)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
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
