import SwiftUI
import AIUsageDashboardCore

/// Menu-bar popover (redesign mockup 5): TOTAL TODAY hero with Δ vs yesterday
/// and a mini area sparkline, one compact row per available provider (brand
/// mark · thin utilization bar · today value), and a footer with last-sync +
/// OPEN DASHBOARD. Dense tier — all real published snapshot state, honest "—"
/// when a baseline is absent. The compact status-bar label (`MenuBarLabel`) and
/// `MaxxerMath` pace/tightest logic are untouched (Round-2 contract).
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var activeSnapshots: [ProviderSnapshot] {
        ProviderID.allCases.compactMap { providerID -> ProviderSnapshot? in
            guard !ProviderVisibility.isHidden(providerID),
                  viewModel.isAvailable(providerID),
                  let snapshot = viewModel.snapshot(for: providerID) else { return nil }
            return snapshot
        }
    }

    // MARK: Aggregated today trend (real snapshot data)
    // NOTE(Wave 2): once WP-1's §4 VM props land, `overviewDelta` /
    // `overviewTrend` replace these two local aggregations verbatim.

    /// Cross-provider total per day for the trailing week, oldest→newest.
    private var weeklyTotals: [Int] {
        let calendar = Calendar.current
        let today = DateHelpers.startOfToday()
        return (0..<7).reversed().compactMap { daysBack -> Int? in
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return nil }
            let sum = activeSnapshots.reduce(0) { $0 + ($1.dailyTotals?[day] ?? 0) }
            return sum
        }
    }

    /// Signed % vs yesterday. Nil when yesterday is zero/unknown — no fake baseline.
    private var deltaVsYesterday: Double? {
        let calendar = Calendar.current
        let today = DateHelpers.startOfToday()
        guard let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        let yesterday = activeSnapshots.reduce(0) { $0 + ($1.dailyTotals?[yesterdayDate] ?? 0) }
        guard yesterday > 0 else { return nil }
        let todayTotal = viewModel.menuBarTodayTotal
        return (Double(todayTotal) - Double(yesterday)) / Double(yesterday) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                surfacePanel {
                    SurfaceStateView(
                        kind: .error(headline: "Sync failed", detail: errorMessage),
                        compact: true,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
            } else if activeSnapshots.isEmpty && viewModel.isLoading {
                surfacePanel {
                    SurfaceStateView(kind: .loading(message: "Syncing"), compact: true)
                }
            } else if activeSnapshots.isEmpty {
                surfacePanel {
                    SurfaceStateView(
                        kind: .empty(
                            headline: "No active providers",
                            hint: "Run an AI CLI, then it shows up here."
                        ),
                        compact: true
                    )
                }
            } else {
                heroPanel
                providersPanel
            }

            footer
        }
        .padding(14)
        .frame(width: 280)
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

    private var heroPanel: some View {
        surfacePanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("TOTAL TODAY")
                    .font(.mono(size: 9))
                    .tracking(0.6)
                    .foregroundColor(PadzyTheme.muted)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TokenFormatter.format(viewModel.menuBarTodayTotal))
                        .font(.mono(size: 28))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let delta = deltaVsYesterday {
                        DeltaLabel(delta: delta)
                    } else {
                        Text("—")
                            .font(.mono(size: 11))
                            .foregroundColor(PadzyTheme.muted)
                    }
                }

                AreaTrendChart(values: weeklyTotals)
                    .frame(height: 30)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Providers

    private var providersPanel: some View {
        surfacePanel {
            VStack(spacing: 8) {
                ForEach(Array(activeSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    providerRow(snapshot)
                    if index < activeSnapshots.count - 1 {
                        HairlineDivider()
                    }
                }
            }
        }
    }

    private func providerRow(_ snapshot: ProviderSnapshot) -> some View {
        // Tightest live window for this provider — the thin bar under the name.
        let tightest = viewModel.utilization
            .filter { $0.providerID == snapshot.providerID }
            .max { $0.usedPercent < $1.usedPercent }

        return HStack(spacing: 8) {
            ProviderBrandMark(snapshot.providerID, size: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.displayName.uppercased())
                    .font(.mono(size: 10))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)

                if let tightest {
                    GeometryReader { geo in
                        let clamped = max(0, min(100, tightest.usedPercent))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(PadzyTheme.muted.opacity(0.3))
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(ProviderOverviewRow.thresholdColor(tightest.usedPercent))
                                .frame(width: geo.size.width * CGFloat(clamped / 100.0))
                        }
                    }
                    .frame(height: 3)
                } else {
                    Text("NO LIVE QUOTA")
                        .font(.mono(size: 8))
                        .foregroundColor(PadzyTheme.muted)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(TokenFormatter.format(snapshot.todayUsage.totalTokens))
                    .font(.mono(size: 11))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.ink)
                if let tightest {
                    Text("\(Int(round(tightest.usedPercent)))%")
                        .font(.mono(size: 9))
                        .monospacedDigit()
                        .foregroundColor(ProviderOverviewRow.thresholdColor(tightest.usedPercent))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(snapshot.displayName), \(TokenFormatter.format(snapshot.todayUsage.totalTokens)) tokens today"
            + (tightest.map { ", \(Int(round($0.usedPercent))) percent of tightest window" } ?? "")
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            HairlineDivider()

            HStack {
                Text("SYNCED \(viewModel.lastSyncedAt.map { timeFormatter.string(from: $0) } ?? "NEVER")")
                    .font(.mono(size: 9))
                    .monospacedDigit()
                    .foregroundColor(PadzyTheme.muted)
                Spacer()
            }

            // Single primary action — the one accent button in the popover.
            Button(action: {
                openWindow(id: "dashboard-window")
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Text("OPEN DASHBOARD")
                    .font(.mono(size: 11))
                    .foregroundColor(PadzyTheme.ground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                            .fill(PadzyTheme.accent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                footerLink("SETTINGS") {
                    viewModel.showingSettings = true
                    openWindow(id: "dashboard-window")
                    NSApp.activate(ignoringOtherApps: true)
                }
                footerDot
                footerLink("UPDATES") {
                    AppDelegate.shared?.checkForUpdates()
                }
                footerDot
                footerLink("QUIT") {
                    NSApp.terminate(nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footerDot: some View {
        Text("·")
            .font(.mono(size: 10))
            .foregroundColor(PadzyTheme.muted)
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mono(size: 10))
                .foregroundColor(PadzyTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Building blocks

    /// Compact rounded surface panel (Dense-tier sibling of `SectionCard`).
    private func surfacePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                    .fill(PadzyTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                    .stroke(PadzyTheme.muted.opacity(0.22), lineWidth: 1)
            )
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
            quotaWindows: [QuotaWindow(providerID: .claudeCode, type: .weekly, used: 94, limit: 100,
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
            todayUsage: .unavailable, weekUsage: .unavailable,
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
