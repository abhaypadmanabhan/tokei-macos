import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Read-only mirror of the Settings toggle — drives which empty-state hint the
    /// Antigravity quota section shows (off vs. on-but-not-syncing yet).
    @AppStorage("antigravityOnlineQuotaEnabled") private var antigravityOnlineQuotaEnabled = false

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

    private var capabilityTier: ProviderCapabilityTier {
        ProviderCapabilityTier.classify(selectedSnapshot)
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

    /// Connections is now the Agents tab, so routing there is a tab selection —
    /// it updates `homeTab` so the tab bar highlight and the mounted pane agree.
    private func openConnections() {
        select(tab: .agents)
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

    /// One mono line disclosing the capability tier + the exact local path(s)
    /// Tokei reads for this provider. Shared by the loaded and plan-only surfaces
    /// so the disclosure never depends on which branch rendered.
    private func sourceDisclosureLine(providerID: ProviderID, tier: ProviderCapabilityTier) -> some View {
        Text("\(tier.label)  ·  \(ProviderMetadata.localPaths(for: providerID).joined(separator: ", "))")
            .font(.mono(size: 10))
            .foregroundColor(PadzyTheme.muted)
            .lineLimit(1)
            .truncationMode(.middle)
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
        } else if capabilityTier == .planOnly {
            capabilityPane
        } else if let snapshot = selectedSnapshot {
            // Full-metrics detail (redesign mockup 1), analytics from the frozen
            // §4 DashboardViewModel surface.
            ProviderDetailView(
                snapshot: snapshot,
                trend: viewModel.trend(for: snapshot.providerID),
                thisWeek: viewModel.thisWeek(for: snapshot.providerID),
                heatmap: viewModel.heatmap(for: snapshot.providerID),
                peakHour: viewModel.peakHour(for: snapshot.providerID),
                lastSyncedAt: viewModel.lastSyncedAt
            )
        } else {
            SurfaceStateView(header: "USAGE", kind: .loading(message: "Reading local logs"))
        }
    }

    /// Honest surface for a provider that has a plan/quota/cost signal but no
    /// token-usage data locally (e.g. Cursor offline, Antigravity). Never shows
    /// the big TODAY hero, since token counts are genuinely unavailable here —
    /// showing "0" would read as real zero usage instead of "not measured."
    private var capabilityPane: some View {
        let providerID = viewModel.selectedProvider
        let snapshot = selectedSnapshot
        let plan = snapshot.flatMap { ProviderMetadata.planText(from: $0.warnings) }
        let creditsWindow = snapshot?.quotaWindows.first { $0.type == .credits }
        let acceptedLinesToday = providerID == .cursor ? snapshot?.dailyTotals?[DateHelpers.startOfToday()] : nil
        // Honest per-model usage text Core already composes (e.g. "Cursor: 214 requests
        // this billing month since Jul 1, 2026") for uncapped accounts that get no gauge.
        // The "Plan:" info warning is parsed into `plan` above and shown separately, so
        // it's excluded here to avoid printing it twice.
        let usageInfoLines = (snapshot?.warnings ?? []).filter {
            $0.level == .info && $0.message.range(of: "Plan:", options: [.caseInsensitive]) == nil
        }.map(\.message)

        let cappedWindows = (snapshot?.quotaWindows ?? []).filter {
            $0.type != .credits && $0.confidence != .unavailable
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                planHeader(providerID: providerID, snapshot: snapshot)

                // Plan hero — mirrors the full-detail TODAY hero: big display value,
                // StatCard tiles for what IS measurable (credits, accepted lines),
                // credits balance as the trailing circular gauge.
                SectionCard("Plan", trailing: {
                    if let creditsWindow, creditsWindow.confidence != .unavailable {
                        ConfidenceBadge(confidence: creditsWindow.confidence)
                    }
                }) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text((plan ?? "—").uppercased())
                                .font(.display(size: 34, weight: .black))
                                .foregroundColor(PadzyTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)

                            let creditsTile: (kicker: String, value: String)? = creditsWindow.flatMap { window in
                                if let used = window.used {
                                    let usedText = TokenFormatter.format(Int(round(used)))
                                    if let limit = window.limit, limit > 0 {
                                        return ("Credits used", "\(usedText) / \(TokenFormatter.format(Int(round(limit))))")
                                    }
                                    return ("Credits used", usedText)
                                }
                                // Balance-style credits (e.g. Codex purchasable): the value is
                                // credits REMAINING, not used — label it honestly as "left".
                                if let remaining = window.remaining {
                                    let remText = TokenFormatter.format(Int(round(remaining)))
                                    if let limit = window.limit, limit > 0 {
                                        return ("Credits left", "\(remText) / \(TokenFormatter.format(Int(round(limit))))")
                                    }
                                    return ("Credits left", remText)
                                }
                                return nil
                            }
                            if creditsTile != nil || acceptedLinesToday != nil {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                                    if let creditsTile {
                                        StatCard(kicker: creditsTile.kicker, value: creditsTile.value)
                                    }
                                    if let acceptedLinesToday {
                                        StatCard(kicker: "Accepted lines today",
                                                 value: TokenFormatter.format(acceptedLinesToday))
                                    }
                                }
                            }

                            ForEach(usageInfoLines, id: \.self) { line in
                                Text(line)
                                    .font(.mono(size: 11))
                                    .foregroundColor(PadzyTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let creditsWindow, let used = creditsWindow.used {
                            CircularGauge(
                                percent: creditsWindow.limit.map { $0 > 0 ? used / $0 * 100 : used } ?? used,
                                label: "credits used",
                                size: 96
                            )
                        }
                    }
                }

                // Quota — Antigravity's per-model weekly/5h groups, or any other
                // capped window a provider emits. Same bar language as the full
                // detail's LIMITS card (threshold color, RESETS, tightest gauge).
                if providerID == .antigravity {
                    SectionCard("Model quota") {
                        antigravityQuotaSection(snapshot)
                    }
                } else if !cappedWindows.isEmpty {
                    SectionCard("Limits") {
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(cappedWindows) { window in
                                    quotaGaugeRow(window)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            tightestGauge(in: cappedWindows)
                        }
                    }
                }

                // Honest disclosure that token-level usage is genuinely unmeasured
                // here — never a fake "0" hero. Plus the Cursor online opt-in.
                SectionCard("Token usage") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOT MEASURED LOCALLY")
                            .font(.mono(size: 11))
                            .tracking(11 * 0.08)
                            .foregroundColor(PadzyTheme.ink)
                        Text("Token-level usage isn't measured locally for \(snapshot?.displayName ?? providerID.rawValue). The plan and quota above are what Tokei can read honestly.")
                            .font(.mono(size: 10))
                            .foregroundColor(PadzyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if providerID == .cursor {
                        Button(action: { openSettings() }) {
                            Text("ENABLE ONLINE IN SETTINGS")
                                .font(.mono(size: 12))
                                .foregroundColor(PadzyTheme.ground)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                                        .fill(PadzyTheme.accent)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }

    /// Plan-only header, mirroring the full-detail header (brand mark · name ·
    /// PLAN ONLY status pill · watching path · last sync) so plan-only providers
    /// read as first-class in the redesign, not a downgraded pane.
    private func planHeader(providerID: ProviderID, snapshot: ProviderSnapshot?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderBrandMark(providerID, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text((snapshot?.displayName ?? providerID.rawValue).uppercased())
                        .font(.display(size: 20, weight: .black))
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                    planStatusPill
                }
                Text("WATCHING \(ProviderMetadata.localPaths(for: providerID).joined(separator: ", "))")
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text("LAST SYNC")
                    .font(.mono(size: 9))
                    .tracking(0.6)
                    .foregroundColor(PadzyTheme.muted)
                Text(viewModel.lastSyncedAt.map { Self.planSyncFormatter.string(from: $0) } ?? "NEVER")
                    .font(.mono(size: 12))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
            }
        }
    }

    /// Quiet hairline status pill — status, never action, so it never takes the accent.
    private var planStatusPill: some View {
        Text("PLAN ONLY")
            .font(.mono(size: 9))
            .tracking(0.6)
            .foregroundColor(PadzyTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.pill, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.4), lineWidth: 1)
            )
            .fixedSize()
    }

    private static let planSyncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Antigravity's weekly + 5-hour windows, grouped by model group (`label`,
    /// e.g. "Gemini Models" / "Claude and GPT models") and rendered under a group
    /// heading — order-preserving so the groups display in the order Core emits
    /// them (Gemini first, then Claude/GPT), never re-sorted alphabetically.
    private struct AntigravityQuotaGroup: Identifiable {
        var id: String { label }
        let label: String
        let windows: [QuotaWindow]
    }

    private func groupedAntigravityWindows(_ windows: [QuotaWindow]) -> [AntigravityQuotaGroup] {
        var order: [String] = []
        var buckets: [String: [QuotaWindow]] = [:]
        for window in windows {
            let label = window.label ?? "Model Quota"
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(window)
        }
        return order.map { label in
            let sorted = (buckets[label] ?? []).sorted { quotaTypeSortKey($0.type) < quotaTypeSortKey($1.type) }
            return AntigravityQuotaGroup(label: label, windows: sorted)
        }
    }

    private func quotaTypeSortKey(_ type: QuotaWindowType) -> Int {
        switch type {
        case .weekly: return 0
        case .fiveHour: return 1
        default: return 2
        }
    }

    @ViewBuilder
    private func antigravityQuotaSection(_ snapshot: ProviderSnapshot?) -> some View {
        let windows = (snapshot?.quotaWindows ?? []).filter {
            $0.confidence != .unavailable
        }
        let groups = groupedAntigravityWindows(windows)

        VStack(alignment: .leading, spacing: 12) {
            if !antigravityOnlineQuotaEnabled {
                SurfaceStateView(
                    kind: .empty(headline: "Live quota disabled", hint: "Enable in Settings to see weekly and 5-hour model quota."),
                    compact: true
                )
            } else if groups.isEmpty {
                SurfaceStateView(
                    kind: .empty(headline: "No live quota yet", hint: "Open Antigravity to sync."),
                    compact: true
                )
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.label.uppercased())
                                    .font(.mono(size: 10))
                                    .tracking(10 * 0.08)
                                    .foregroundColor(PadzyTheme.muted)
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(group.windows) { window in
                                        quotaGaugeRow(window)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    tightestGauge(in: windows)
                }
            }
        }
    }

    private func quotaWindowTypeLabel(_ type: QuotaWindowType) -> String {
        switch type {
        case .fiveHour: return "5-HOUR"
        case .perModel: return "PER MODEL"
        default: return type.rawValue.uppercased()
        }
    }

    /// One quota window in the full-detail LIMITS bar language: threshold-colored
    /// 6px rounded fill, RESETS countdown, `!!` non-color critical marker.
    private func quotaGaugeRow(_ window: QuotaWindow) -> some View {
        let percent = window.used ?? 0
        let clamped = max(0, min(100, percent))
        let color = ProviderOverviewRow.thresholdColor(percent)
        let isCritical = ProviderOverviewRow.isCritical(percent)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(quotaWindowTypeLabel(window.type))
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                ConfidenceBadge(confidence: window.confidence)
                Spacer(minLength: 8)
                if let resetAt = window.resetAt {
                    Text("RESETS \(formatCountdown(from: resetAt))")
                        .font(.mono(size: 10))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.muted)
                }
                HStack(spacing: 3) {
                    if isCritical {
                        Text("!!")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.accent)
                    }
                    Text("\(Int(round(percent)))%")
                        .font(.mono(size: 12))
                        .monospacedDigit()
                        .foregroundColor(color)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(PadzyTheme.muted.opacity(0.25))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(clamped / 100.0))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelForQuotaWindow(window))
    }

    /// Circular gauge of the single tightest window in a set — the same trailing
    /// gauge the full detail's LIMITS card shows for the session window.
    @ViewBuilder
    private func tightestGauge(in windows: [QuotaWindow]) -> some View {
        let tightest = windows
            .filter { $0.used != nil }
            .max { ($0.used ?? 0) < ($1.used ?? 0) }
        if let tightest, let used = tightest.used {
            CircularGauge(
                percent: tightest.limit.map { $0 > 0 ? used / $0 * 100 : used } ?? used,
                label: "of \(quotaWindowTypeLabel(tightest.type).lowercased()) limit",
                size: 96
            )
        }
    }

    private func formatCountdown(from date: Date) -> String {
        let _ = countdownTick
        let timeInterval = date.timeIntervalSince(Date())
        guard timeInterval > 0 else { return "00:00" }
        let totalHours = Int(timeInterval) / 3600
        // Windows that reset days out (weekly quota, monthly billing) read better as
        // "4d 12h" than a five-digit hour count ticking every second.
        if totalHours >= 24 {
            let days = totalHours / 24
            let hours = totalHours % 24
            return "\(days)d \(hours)h"
        }
        let hours = totalHours
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func accessibilityLabelForQuotaWindow(_ window: QuotaWindow) -> String {
        let provider = window.providerID.rawValue == "claude_code" ? "Claude" : window.providerID.rawValue.capitalized
        let typeName = window.type.rawValue
        let usedPercent = window.used.map { "\(Int(round($0))) percent used" } ?? "unknown usage"
        let resets: String
        if let resetAt = window.resetAt {
            let diff = resetAt.timeIntervalSince(Date())
            if diff <= 0 {
                resets = ", resets now"
            } else {
                let hours = Int(diff) / 3600
                let minutes = (Int(diff) % 3600) / 60
                if hours > 0 {
                    resets = ", resets in \(hours) hour\(hours == 1 ? "" : "s")"
                } else {
                    resets = ", resets in \(minutes) minute\(minutes == 1 ? "" : "s")"
                }
            }
        } else {
            resets = ""
        }
        return "\(provider) \(typeName) window \(usedPercent)\(resets)"
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
