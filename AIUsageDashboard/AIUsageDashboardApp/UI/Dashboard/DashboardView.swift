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

    @State private var pulseOpacity: Double = 1.0
    @State private var countdownTick = Date()
    private let countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

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

    /// Daily totals sorted by day, most recent last, limited to the trailing `days`.
    private func dailySeries(days: Int?) -> [Int] {
        guard let totals = selectedSnapshot?.dailyTotals, !totals.isEmpty else { return [] }
        let sorted = totals.sorted { $0.key < $1.key }.map(\.value)
        if let days, sorted.count > days { return Array(sorted.suffix(days)) }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(PadzyTheme.muted.opacity(0.3))
                    .frame(width: 1)
                rightPane
            }
            statusStrip
        }
        .background(PadzyTheme.ground)
        .preferredColorScheme(.dark)
        .frame(minWidth: 860, minHeight: 560)
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .up:
                selectPreviousVisible()
                section = .provider(viewModel.selectedProvider)
                viewModel.showingSettings = false
            case .down:
                selectNextVisible()
                section = .provider(viewModel.selectedProvider)
                viewModel.showingSettings = false
            default:
                break
            }
        }
        .onReceive(countdownTimer) { _ in
            countdownTick = Date()
        }
        .task {
            viewModel.beginAutoSync()
            await viewModel.refresh()
        }
    }

    // MARK: 01 / PROVIDERS

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            overviewSidebarRow
            HairlineDivider()

            EditorialKicker(number: "01", title: "PROVIDERS")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            HairlineDivider()

            ForEach(ProviderID.allCases, id: \.self) { providerID in
                SidebarProviderRow(providerID: providerID, section: $section)
            }
            Spacer(minLength: 0)
            settingsSidebarRow
        }
        .frame(width: 230)
    }

    /// Top sidebar entry that routes the right pane to the consolidated Overview.
    /// Mirrors `settingsSidebarRow`'s 2px leading accent tick + surface fill on active.
    private var overviewSidebarRow: some View {
        let isActive = section == .overview
        return Button(action: {
            section = .overview
            viewModel.showingSettings = false
        }) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? PadzyTheme.accent : Color.clear)
                    .frame(width: 2)
                Text("00 / OVERVIEW")
                    .font(.display(size: 13, weight: .bold))
                    .foregroundColor(isActive ? PadzyTheme.ink : PadzyTheme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                Spacer(minLength: 0)
            }
            .background(isActive ? PadzyTheme.surface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    /// Bottom-pinned sidebar entry that swaps the right pane to the in-app Settings
    /// surface. Mirrors ProviderCard's 2px leading accent tick + surface fill on active.
    private var settingsSidebarRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineDivider()
            Button(action: {
                section = .settings
                viewModel.showingSettings = true
            }) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(section == .settings ? PadzyTheme.accent : Color.clear)
                        .frame(width: 2)
                    Text("SETTINGS")
                        .font(.display(size: 13, weight: .bold))
                        .foregroundColor(section == .settings ? PadzyTheme.ink : PadzyTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    Spacer(minLength: 0)
                }
                .background(section == .settings ? PadzyTheme.surface : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
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
    private var rightPane: some View {
        switch section {
        case .overview:
            OverviewView(
                onOpen: { providerID in
                    section = .provider(providerID)
                    viewModel.selectedProvider = providerID
                    viewModel.showingSettings = false
                },
                onConnect: { section = .connections }
            )
        case .connections:
            ConnectionsView()
        case .settings:
            SettingsPane()
        case .provider:
            providerDetailPane
        }
    }

    @ViewBuilder
    private var providerDetailPane: some View {
        if let errorMessage = viewModel.errorMessage {
            SurfaceStateView(
                kicker: ("02", "USAGE"),
                kind: .error(headline: "Sync failed", detail: errorMessage),
                onRetry: { Task { await viewModel.refresh() } }
            )
        } else if viewModel.selectedProvider == .claudeCode && !isClaudeInstalled {
            emptyState
        } else if selectedSnapshot == nil && viewModel.isLoading {
            SurfaceStateView(
                kicker: ("02", "USAGE"),
                kind: .loading(message: "Reading local logs")
            )
        } else if !selectedHasData {
            SurfaceStateView(
                kicker: ("02", "USAGE"),
                kind: .empty(
                    headline: "No usage data",
                    hint: "No data yet at \(ProviderMetadata.localPaths(for: viewModel.selectedProvider).joined(separator: ", ")). Run it once, then use Sync Now below."
                )
            )
        } else if capabilityTier == .planOnly {
            capabilityPane
        } else {
            usagePane
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

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                EditorialKicker(number: "02", title: "USAGE")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            sourceDisclosureLine(providerID: providerID, tier: .planOnly)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                if let plan {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLAN")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                        Text(plan.uppercased())
                            .font(.display(size: 20, weight: .black))
                            .foregroundColor(PadzyTheme.ink)
                    }
                }

                if let acceptedLinesToday {
                    breakdownItem("ACCEPTED LINES TODAY", acceptedLinesToday)
                }

                if let creditsWindow {
                    quotaGaugeRow(creditsWindow)
                }

                if providerID == .antigravity {
                    antigravityQuotaSection(snapshot)
                } else {
                    // Honest gauge for any other capped window a provider emits (e.g. a
                    // Cursor model with a real `maxRequestUsage`). Uncapped accounts emit
                    // no such window, so this renders nothing — matching "no fake gauge."
                    let cappedWindows = (snapshot?.quotaWindows ?? []).filter {
                        $0.type != .credits && $0.confidence != .unavailable
                    }
                    ForEach(cappedWindows) { window in
                        quotaGaugeRow(window)
                    }
                }

                ForEach(usageInfoLines, id: \.self) { line in
                    Text(line.uppercased())
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("TOKEN USAGE UNAVAILABLE LOCALLY")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.muted)

                if providerID == .cursor {
                    Button(action: {
                        section = .settings
                        viewModel.showingSettings = true
                    }) {
                        Text("ENABLE ONLINE IN SETTINGS")
                            .font(.mono(size: 12))
                            .foregroundColor(PadzyTheme.ground)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(PadzyTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer(minLength: 16)
        }
    }

    private var usagePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                EditorialKicker(number: "02", title: "USAGE")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            sourceDisclosureLine(providerID: viewModel.selectedProvider, tier: .fullMetrics)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("01 / TODAY")
                    .font(.mono(size: 12))
                    .tracking(12 * 0.04)
                    .foregroundColor(PadzyTheme.muted)

                Text(TokenFormatter.format(selectedSnapshot?.todayUsage.totalTokens))
                    .font(.mono(size: 150))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
                    .frame(maxWidth: .infinity, alignment: .leading)

                usageBreakdown
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer(minLength: 16)

            // Quota Limits Section (renders only if has active quota windows)
            if let activeWindows = selectedSnapshot?.quotaWindows.filter({ $0.confidence != .unavailable }), !activeWindows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EditorialKicker(number: limitsSectionNumber, title: "LIMITS")
                        .padding(.horizontal, 28)
                        .padding(.top, 16)

                    VStack(spacing: 12) {
                        ForEach(activeWindows) { window in
                            quotaGaugeRow(window)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                }
                Spacer(minLength: 16)
                HairlineDivider()
            } else {
                HairlineDivider()
            }

            HStack(alignment: .top, spacing: 0) {
                metricBlock(number: metricBlockNumber(baseNumber: 2), title: "7D ROLLING",
                            usage: selectedSnapshot?.weekUsage, series: dailySeries(days: 7))
                verticalHairline
                metricBlock(number: metricBlockNumber(baseNumber: 3), title: "30D ROLLING",
                            usage: selectedSnapshot?.monthUsage, series: dailySeries(days: 30))
                verticalHairline
                metricBlock(number: metricBlockNumber(baseNumber: 4), title: "LIFETIME",
                            usage: selectedSnapshot?.lifetimeUsage, series: dailySeries(days: nil), cost: selectedSnapshot?.costUsage)
            }
            .frame(height: 168)
        }
    }

    private var limitsSectionNumber: String {
        "02"
    }

    private func metricBlockNumber(baseNumber: Int) -> String {
        let hasLimits = !(selectedSnapshot?.quotaWindows.filter { $0.confidence != .unavailable }.isEmpty ?? true)
        let num = hasLimits ? baseNumber + 1 : baseNumber
        return String(format: "%02d", num)
    }

    private var usageBreakdown: some View {
        HStack(spacing: 24) {
            if let snapshot = selectedSnapshot {
                breakdownItem("INPUT", snapshot.todayUsage.inputTokens)
                breakdownItem("OUTPUT", snapshot.todayUsage.outputTokens)
                breakdownItem("CACHE READ", snapshot.todayUsage.cacheReadTokens)
                breakdownItem("CACHE WRITE", snapshot.todayUsage.cacheCreationTokens)
                if let cost = snapshot.costUsage, let amount = cost.amount {
                    breakdownItem("COST", String(format: "$%.2f", amount))
                }
                let confidence = snapshot.todayUsage.confidence
                if confidence != .unavailable {
                    ConfidenceBadge(confidence: confidence)
                }
            }
        }
    }

    private func breakdownItem(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
            Text(TokenFormatter.format(value))
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.ink)
        }
    }

    private func breakdownItem(_ label: String, _ valueStr: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
            Text(valueStr)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.ink)
        }
    }

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
            Text("MODEL QUOTA")
                .font(.mono(size: 11))
                .foregroundColor(PadzyTheme.muted)

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
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label.uppercased())
                                .font(.display(size: 13, weight: .bold))
                                .foregroundColor(PadzyTheme.ink)
                            VStack(spacing: 8) {
                                ForEach(group.windows) { window in
                                    quotaGaugeRow(window)
                                }
                            }
                        }
                    }
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

    private func quotaGaugeRow(_ window: QuotaWindow) -> some View {
        let percent = window.used.map { Int(round($0)) } ?? 0
        let isCritical = percent > 90

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    let resetLabel = window.resetAt.map { " · RESETS \(formatCountdown(from: $0))" } ?? ""
                    Text("\(quotaWindowTypeLabel(window.type))\(resetLabel)")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                    ConfidenceBadge(confidence: window.confidence)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // 1px hairline track
                        Rectangle()
                            .fill(PadzyTheme.muted.opacity(0.3))
                            .frame(height: 1)

                        // Flat accent fill proportional to used_percent
                        if let used = window.used {
                            let clamped = max(0, min(100, used))
                            let fillWidth = geo.size.width * CGFloat(clamped / 100.0)
                            Rectangle()
                                .fill(PadzyTheme.accent)
                                .frame(width: fillWidth, height: 1)
                        }
                    }
                }
                .frame(height: 1)
            }

            // Right-aligned mono 29% / 100
            HStack(spacing: 4) {
                if isCritical {
                    Text("!!")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.accent)
                }
                Text("\(percent)% / 100")
                    .font(.mono(size: 11))
                    .foregroundColor(isCritical ? PadzyTheme.accent : PadzyTheme.ink)
            }
            .monospacedDigit()
            .frame(width: 80, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelForQuotaWindow(window))
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

    private var verticalHairline: some View {
        Rectangle()
            .fill(PadzyTheme.muted.opacity(0.3))
            .frame(width: 1)
    }

    private func metricBlock(number: String, title: String, usage: TokenUsage?, series: [Int], cost: CostUsage? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("\(number) / \(title)")
                    .font(.mono(size: 11))
                    .tracking(11 * 0.04)
                    .foregroundColor(PadzyTheme.muted)

                Spacer()

                if let cost = cost, let amount = cost.amount {
                    HStack(spacing: 4) {
                        Text("COST")
                            .font(.mono(size: 9))
                            .foregroundColor(PadzyTheme.muted)
                        Text(String(format: "$%.2f", amount))
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.ink)
                    }
                }
            }

            Text(TokenFormatter.format(usage?.totalTokens))
                .font(.mono(size: 40))
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Sparkline(values: series)
                .frame(height: 44)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 03 / STATUS

    private var statusStrip: some View {
        VStack(spacing: 0) {
            if let warnings = selectedSnapshot?.warnings.filter({ $0.level != .info }), !warnings.isEmpty {
                HairlineDivider()
                HStack(spacing: 8) {
                    Text("!!")
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.accent)
                    Text(warnings.map(\.message).joined(separator: "  ·  ").uppercased())
                        .font(.mono(size: 10))
                        .foregroundColor(PadzyTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            HairlineDivider()
            HStack(spacing: 16) {
                Text("03 / STATUS")
                    .font(.mono(size: 11))
                    .tracking(11 * 0.04)
                    .foregroundColor(PadzyTheme.muted)

                if viewModel.isLoading {
                    Rectangle()
                        .fill(PadzyTheme.accent)
                        .frame(width: 6, height: 6)
                        .opacity(pulseOpacity)
                        .onAppear {
                            if !reduceMotion {
                                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                    pulseOpacity = 0.2
                                }
                            }
                        }
                }

                Text(statusLine)
                    .font(.mono(size: 12))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)

                Spacer()

                Button(action: { Task { await viewModel.refresh() } }) {
                    Text("SYNC NOW")
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(PadzyTheme.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Sync now")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var statusLine: String {
        let synced = viewModel.lastSyncedAt.map { Self.timeFormatter.string(from: $0) } ?? "NEVER"
        let confidence = selectedSnapshot?.todayUsage.confidence.displayName.uppercased() ?? "—"
        let pathName = ProviderMetadata.localPaths(for: viewModel.selectedProvider).first ?? "—"
        return "SYNCED \(synced)  ·  \(confidence)  ·  WATCHING \(pathName)"
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialKicker(number: "02", title: "USAGE")
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

/// One sidebar entry, gated by the per-provider hide toggle (Settings). Holds its
/// own `@AppStorage` so hiding/showing a provider updates the sidebar instantly.
private struct SidebarProviderRow: View {
    let providerID: ProviderID
    @Binding var section: AppSection
    @EnvironmentObject private var viewModel: DashboardViewModel
    @AppStorage private var isHidden: Bool

    init(providerID: ProviderID, section: Binding<AppSection>) {
        self.providerID = providerID
        _section = section
        _isHidden = AppStorage(wrappedValue: false, ProviderVisibility.key(for: providerID))
    }

    var body: some View {
        if !isHidden {
            let isSelected = viewModel.selectedProvider == providerID && section == .provider(providerID)
            let isAvailable = viewModel.isAvailable(providerID)
            let snapshot = viewModel.snapshot(for: providerID)
            let tier = ProviderCapabilityTier.classify(snapshot)

            Button(action: {
                if isAvailable {
                    section = .provider(providerID)
                    viewModel.selectedProvider = providerID
                    viewModel.showingSettings = false
                }
            }) {
                ProviderCard(
                    providerID: providerID,
                    displayName: snapshot?.displayName ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ").uppercased(),
                    todayUsage: snapshot?.todayUsage,
                    tier: tier,
                    isSelected: isSelected,
                    isAvailable: isAvailable
                )
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .accessibilityAddTraits(.isButton)

            HairlineDivider()
        }
    }
}
