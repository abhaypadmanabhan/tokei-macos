import SwiftUI
import AIUsageDashboardCore

/// The provider drill-in surface: resolves to error → tailored empty (Claude not
/// installed) → loading → generic empty → loaded, in that precedence.
///
/// Lifted out of `DashboardView` as its own view because everything here answers one
/// question — "what do we render for the selected provider?" — and none of it is shell
/// concern. The route-target derivation lives here too, next to the chip that is its
/// only consumer.
struct DashboardProviderPane: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    /// Opens the Settings drawer (the Cursor "enable online" hand-off).
    var onEnableOnline: () -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            SurfaceStateView(
                header: "USAGE",
                kind: .error(headline: "Sync failed", detail: errorMessage),
                onRetry: { Task { await viewModel.refresh() } }
            )
        } else if viewModel.selectedProvider == .claudeCode && !isClaudeInstalled {
            claudeMissingState
        } else if selectedSnapshot == nil && viewModel.isLoading {
            SurfaceStateView(
                header: "USAGE",
                kind: .loading(message: "Reading local logs")
            )
        } else if !selectedHasData {
            SurfaceStateView(
                header: "USAGE",
                kind: .empty(headline: "No usage data", hint: noDataHint)
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
                onEnableOnline: onEnableOnline
            )
        } else {
            SurfaceStateView(header: "USAGE", kind: .loading(message: "Reading local logs"))
        }
    }

    // MARK: Derived state

    /// Names the paths we actually watch, so "no data" points somewhere actionable.
    private var noDataHint: String {
        let paths = ProviderMetadata.localPaths(for: viewModel.selectedProvider)
            .joined(separator: ", ")
        return "No data yet at \(paths). Run it once, then use Sync Now below."
    }

    private var selectedSnapshot: ProviderSnapshot? {
        viewModel.snapshot(for: viewModel.selectedProvider)
    }

    private var isClaudeInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        return FileManager.default.fileExists(atPath: claudeDir.path)
    }

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

    /// The visible provider worth routing new work to. Delegates to the ONE canonical
    /// rule (`RouteTargetPolicy.human` via `MaxxerMath.routeTarget`) — the same rule
    /// `OverviewView.headroomProviderID` and the agent snapshot use, so no two
    /// surfaces can point at different providers. `nil` until at least two providers
    /// have a *trusted* live reading, so this can no longer nominate a stale
    /// `local_estimate`. Drives the drill-in's green route chip.
    private var routeTargetProviderID: ProviderID? {
        MaxxerMath.routeTarget(in: visibleUtilizations, now: Date())?.providerID
    }

    /// Live readings for providers the user hasn't hidden. `RouteTargetPolicy` has no
    /// opinion on visibility, so the filtering happens here.
    private var visibleUtilizations: [Utilization] {
        viewModel.utilization.filter { !ProviderVisibility.isHidden($0.providerID) }
    }

    // MARK: Empty state

    /// Claude Code isn't installed at all — a different miss from "installed but no
    /// data yet", so it gets its own copy naming the path we watch.
    private var claudeMissingState: some View {
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
