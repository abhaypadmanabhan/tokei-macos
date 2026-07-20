import SwiftUI
import AIUsageDashboardCore

/// The guided Connections screen — the in-app way to turn on a coding agent's
/// live quota read. Every connector is off by default and reads only local /
/// own-account data; this screen is the single, honest opt-in surface (replacing
/// the scattered Settings toggles). Each row owns its provider's `@AppStorage`
/// flag and re-runs the providers on change.
struct ConnectionsView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    /// Opens the shell's Add-agent drawer (overlaid on the whole window).
    var onAddAgent: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Connections")
                    Text("Connect a coding agent to read its live quota. Local-first — off by default.")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                AddAgentButton { onAddAgent() }
                    .fixedSize()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            HairlineDivider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ConnectionRow(
                        providerID: .claudeCode,
                        storageKey: "claudeNetworkUsageEnabled",
                        disclosure: "Reads your own Claude account. May break if Anthropic changes their API.",
                        help: "Run `claude` once to refresh your login."
                    )
                    HairlineDivider()

                    ConnectionRow(
                        providerID: .cursor,
                        storageKey: "cursorNetworkUsageEnabled",
                        disclosure: "Makes an authenticated request to Cursor's servers using your local session token to fetch real token/quota usage.",
                        help: ""
                    )
                    HairlineDivider()

                    ConnectionRow(
                        providerID: .antigravity,
                        storageKey: "antigravityOnlineQuotaEnabled",
                        disclosure: "Reads live quota from the running Antigravity app on your Mac. No token is stored or sent anywhere.",
                        help: "Requires the Antigravity app to be open."
                    )
                    HairlineDivider()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PadzyTheme.ground)
    }
}

// MARK: - Preview

@MainActor
private func mockViewModel(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
    let vm = DashboardViewModel()
    vm.snapshots = snapshots
    return vm
}

@MainActor
private func mockSnapshot(_ id: ProviderID, name: String) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: [],
        todayUsage: .unavailable,
        weekUsage: .unavailable,
        warnings: []
    )
}

#Preview("Connections") {
    ConnectionsView()
        .environmentObject(mockViewModel([
            mockSnapshot(.claudeCode, name: "Claude Code"),
            mockSnapshot(.cursor, name: "Cursor"),
        ]))
        .frame(width: 640, height: 560)
        .background(PadzyTheme.ground)
}
