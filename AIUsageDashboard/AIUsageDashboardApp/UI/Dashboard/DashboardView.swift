import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                viewModel.showingSettings = false
                viewModel.selectPreviousProvider()
            case .down:
                viewModel.showingSettings = false
                viewModel.selectNextProvider()
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
            EditorialKicker(number: "01", title: "PROVIDERS")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            HairlineDivider()

            ForEach(ProviderID.allCases, id: \.self) { providerID in
                let isSelected = viewModel.selectedProvider == providerID
                let isAvailable = viewModel.isAvailable(providerID)
                let snapshot = viewModel.snapshot(for: providerID)

                Button(action: {
                    if isAvailable {
                        viewModel.selectedProvider = providerID
                        viewModel.showingSettings = false
                    }
                }) {
                    ProviderCard(
                        providerID: providerID,
                        displayName: snapshot?.displayName ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ").uppercased(),
                        todayUsage: snapshot?.todayUsage,
                        isSelected: isSelected,
                        isAvailable: isAvailable
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                .accessibilityAddTraits(.isButton)

                HairlineDivider()
            }
            Spacer(minLength: 0)
            settingsSidebarRow
        }
        .frame(width: 230)
    }

    /// Bottom-pinned sidebar entry that swaps the right pane to the in-app Settings
    /// surface. Mirrors ProviderCard's 2px leading accent tick + surface fill on active.
    private var settingsSidebarRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineDivider()
            Button(action: { viewModel.showingSettings = true }) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(viewModel.showingSettings ? PadzyTheme.accent : Color.clear)
                        .frame(width: 2)
                    Text("SETTINGS")
                        .font(.display(size: 13, weight: .bold))
                        .foregroundColor(viewModel.showingSettings ? PadzyTheme.ink : PadzyTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    Spacer(minLength: 0)
                }
                .background(viewModel.showingSettings ? PadzyTheme.surface : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: 02 / USAGE

    /// True when the selected provider has any real signal to render (tokens in
    /// any window, an active quota, or a cost). Drives the empty state.
    private var selectedHasData: Bool {
        guard let snapshot = selectedSnapshot else { return false }
        let tokenTotals = [snapshot.todayUsage.totalTokens, snapshot.weekUsage.totalTokens,
                           snapshot.monthUsage?.totalTokens, snapshot.lifetimeUsage?.totalTokens]
            .compactMap { $0 }
        if tokenTotals.contains(where: { $0 > 0 }) { return true }
        if snapshot.quotaWindows.contains(where: { $0.confidence != .unavailable }) { return true }
        if snapshot.costUsage?.amount != nil { return true }
        return false
    }

    /// Provider-detail surface: resolves to error → tailored empty (Claude not
    /// installed) → loading → generic empty → loaded, in that precedence.
    @ViewBuilder
    private var rightPane: some View {
        if viewModel.showingSettings {
            SettingsPane()
        } else if let errorMessage = viewModel.errorMessage {
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
                    hint: "No local session logs found for this provider yet. Run it once, then use Sync Now below."
                )
            )
        } else {
            usagePane
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

    private func quotaGaugeRow(_ window: QuotaWindow) -> some View {
        let percent = window.used.map { Int(round($0)) } ?? 0
        let isCritical = percent > 90

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    let resetLabel = window.resetAt.map { " · RESETS \(formatCountdown(from: $0))" } ?? ""
                    Text("\(window.type.rawValue.uppercased())\(resetLabel)")
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
        let hours = Int(timeInterval) / 3600
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
        let pathName: String
        switch viewModel.selectedProvider {
        case .claudeCode: pathName = "~/.claude"
        case .codex: pathName = "~/.codex"
        case .cursor: pathName = "~/.cursor"
        case .antigravity: pathName = "~/.antigravity"
        case .cline: pathName = "~/.cline"
        }
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
