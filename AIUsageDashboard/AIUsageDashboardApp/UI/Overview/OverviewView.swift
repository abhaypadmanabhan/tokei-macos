import SwiftUI
import AIUsageDashboardCore

/// The consolidated Overview home — the app's default surface. One aggregate
/// headline ("how maxed am I across every plan") over one glanceable row per
/// visible provider, each collapsed to its **tightest** live-quota window.
/// Deliberately does not duplicate the detail tab's full breakdown; a row is a
/// jump-off point into that detail.
struct OverviewView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Open a provider's detail tab (wired by `DashboardView` to set nav state).
    var onOpen: (ProviderID) -> Void = { _ in }
    /// Route to the Connections screen for a provider with no live quota.
    var onConnect: () -> Void = {}

    /// One display model per visible provider: identity + its tightest window.
    private struct Entry: Identifiable {
        let providerID: ProviderID
        let displayName: String
        let plan: String?
        let tightest: Utilization?
        var id: ProviderID { providerID }
        /// Sort key: tighter windows first; no-quota rows sink to the bottom.
        var rank: Double { tightest?.usedPercent ?? -1 }
    }

    /// Visible providers, each reduced to its tightest window, sorted by that
    /// window's used percent descending (unavailable providers last).
    private var entries: [Entry] {
        ProviderID.allCases
            .filter { !ProviderVisibility.isHidden($0) }
            .map { id in
                let tightest = viewModel.utilization
                    .filter { $0.providerID == id }
                    .max(by: { $0.usedPercent < $1.usedPercent })
                return Entry(
                    providerID: id,
                    displayName: viewModel.snapshot(for: id)?.displayName ?? fallbackName(id),
                    plan: tightest?.plan,
                    tightest: tightest
                )
            }
            .sorted { $0.rank > $1.rank }
    }

    private func fallbackName(_ id: ProviderID) -> String {
        id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var aggregateLine: String {
        guard let agg = viewModel.aggregateUtilization else {
            return "— NO LIVE QUOTA CONNECTED"
        }
        // `aggregateUtilization` is the MEAN of per-provider peaks (Core), so label
        // it "AVG" — "PEAK" would misread as the single highest window.
        return "\(Int(round(agg.usedPercent)))% AVG · \(agg.coveredProviders.count) LIVE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                EditorialKicker(number: "00", title: "OVERVIEW")
                Text(aggregateLine)
                    .font(.mono(size: 22))
                    .monospacedDigit()
                    .foregroundColor(viewModel.aggregateUtilization == nil ? PadzyTheme.muted : PadzyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            HairlineDivider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        ProviderOverviewRow(
                            providerID: entry.providerID,
                            displayName: entry.displayName,
                            plan: entry.plan,
                            tightest: entry.tightest,
                            onOpen: { onOpen(entry.providerID) },
                            onConnect: onConnect
                        )
                        HairlineDivider()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Previews

@MainActor
private func mockViewModel(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    return vm
}

@MainActor
private func mockSnapshot(
    _ id: ProviderID,
    name: String,
    plan: String? = nil,
    windows: [QuotaWindow] = []
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: windows,
        todayUsage: .unavailable,
        weekUsage: .unavailable,
        warnings: plan.map { [ProviderWarning(message: "Plan: \($0)", level: .info)] } ?? []
    )
}

@MainActor
private func window(_ id: ProviderID, _ type: QuotaWindowType, used: Double, inHours: Double) -> QuotaWindow {
    QuotaWindow(
        providerID: id, type: type, used: used, limit: 100,
        resetAt: Date().addingTimeInterval(inHours * 3600),
        confidence: .providerReported, source: "preview"
    )
}

#Preview("All live") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 95, inHours: 105),
                                   window(.claudeCode, .session, used: 40, inHours: 3)]),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro",
                         windows: [window(.cursor, .monthly, used: 78, inHours: 11)]),
            mockSnapshot(.antigravity, name: "Antigravity",
                         windows: [window(.antigravity, .fiveHour, used: 32, inHours: 3)]),
            mockSnapshot(.codex, name: "Codex",
                         windows: [window(.codex, .weekly, used: 12, inHours: 60)]),
            mockSnapshot(.cline, name: "Cline",
                         windows: [window(.cline, .credits, used: 61, inHours: 240)]),
        ]))
        .frame(width: 720, height: 560)
        .background(PadzyTheme.ground)
}

#Preview("Mixed") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code", plan: "Max · yearly",
                         windows: [window(.claudeCode, .weekly, used: 88, inHours: 105)]),
            mockSnapshot(.cursor, name: "Cursor", plan: "Pro"),
            mockSnapshot(.antigravity, name: "Antigravity",
                         windows: [window(.antigravity, .fiveHour, used: 55, inHours: 2)]),
            mockSnapshot(.codex, name: "Codex"),
        ]))
        .frame(width: 640, height: 520)
        .background(PadzyTheme.ground)
}

#Preview("All unavailable") {
    OverviewView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code"),
            mockSnapshot(.cursor, name: "Cursor"),
            mockSnapshot(.antigravity, name: "Antigravity"),
        ]))
        .frame(width: 640, height: 480)
        .background(PadzyTheme.ground)
}
