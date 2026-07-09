import SwiftUI
import AIUsageDashboardCore

/// One coding agent's line on the guided Connections screen: identity + detected
/// state, an **Enable** switch bound to the provider's own `UserDefaults` flag, a
/// muted disclosure line, and — only while enabled but not yet returning data — a
/// help line telling the user the one action that unblocks the live read.
///
/// The switch writes straight to the `@AppStorage` key the connector reads at
/// fetch time. A plain `UserDefaults` write fires no sync, so on every change we
/// re-run the providers; otherwise flipping the switch would appear to "do
/// nothing" until the next file-watcher event (same pattern as the old Settings
/// toggles this screen replaces).
struct ConnectionRow: View {
    let providerID: ProviderID
    let storageKey: String
    let disclosure: String
    let help: String

    @AppStorage private var enabled: Bool
    @EnvironmentObject private var viewModel: DashboardViewModel

    init(providerID: ProviderID, storageKey: String, disclosure: String, help: String) {
        self.providerID = providerID
        self.storageKey = storageKey
        self.disclosure = disclosure
        self.help = help
        // Runtime key — the connector's opt-in flag. Default OFF: no network /
        // RPC read happens until the user flips this switch here.
        _enabled = AppStorage(wrappedValue: false, storageKey)
    }

    /// The provider produced a snapshot this run — its CLI/app is present.
    private var detected: Bool {
        viewModel.snapshot(for: providerID) != nil
    }

    /// Any live quota window came back for this provider.
    private var hasLiveData: Bool {
        viewModel.utilization.contains { $0.providerID == providerID }
    }

    /// Enabled, but no live reading yet — the help line's one unblocking action
    /// is worth surfacing (Claude: refresh login; Antigravity: open the app).
    private var showHelp: Bool {
        enabled && !hasLiveData && !help.isEmpty
    }

    private var displayName: String {
        viewModel.snapshot(for: providerID)?.displayName
            ?? providerID.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                ProviderMark(providerID, size: 22, enabled: enabled)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.display(size: 14, weight: .bold))
                        .foregroundColor(PadzyTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(detected ? "INSTALLED" : "NOT FOUND")
                        .font(.mono(size: 10))
                        .tracking(0.5)
                        .foregroundColor(PadzyTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The one accent in this row: the enable state/action.
                Toggle("Enable", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(PadzyTheme.accent)
                    .onChange(of: enabled) {
                        Task { await viewModel.refresh() }
                    }
                    .accessibilityLabel("Enable \(displayName) live quota")
            }

            Text(disclosure)
                .font(.system(size: 11))
                .foregroundColor(PadzyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showHelp {
                Text(help)
                    .font(.system(size: 11))
                    .foregroundColor(PadzyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    windows: [QuotaWindow] = []
) -> ProviderSnapshot {
    ProviderSnapshot(
        providerID: id,
        displayName: name,
        authStatus: .authenticated,
        quotaWindows: windows,
        todayUsage: .unavailable,
        weekUsage: .unavailable,
        warnings: []
    )
}

@MainActor
private func window(_ id: ProviderID, _ type: QuotaWindowType, used: Double) -> QuotaWindow {
    QuotaWindow(
        providerID: id, type: type, used: used, limit: 100,
        resetAt: Date().addingTimeInterval(3 * 3600),
        confidence: .providerReported, source: "preview"
    )
}

#Preview("Installed + on (live)") {
    // Preview-only keys so on/off states are deterministic per canvas.
    UserDefaults.standard.set(true, forKey: "previewClaudeOn")
    return ConnectionRow(
        providerID: .claudeCode,
        storageKey: "previewClaudeOn",
        disclosure: "Reads your own Claude account. May break if Anthropic changes their API.",
        help: "Run `claude` once to refresh your login."
    )
    .environmentObject(mockViewModel([
        mockSnapshot(.claudeCode, name: "Claude Code",
                     windows: [window(.claudeCode, .weekly, used: 62)])
    ]))
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

#Preview("Installed + on (no data → help)") {
    UserDefaults.standard.set(true, forKey: "previewClaudeStale")
    return ConnectionRow(
        providerID: .claudeCode,
        storageKey: "previewClaudeStale",
        disclosure: "Reads your own Claude account. May break if Anthropic changes their API.",
        help: "Run `claude` once to refresh your login."
    )
    .environmentObject(mockViewModel([
        mockSnapshot(.claudeCode, name: "Claude Code")
    ]))
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

#Preview("Installed + off") {
    UserDefaults.standard.set(false, forKey: "previewCursorOff")
    return ConnectionRow(
        providerID: .cursor,
        storageKey: "previewCursorOff",
        disclosure: "Makes an authenticated request to Cursor's servers using your local session token to fetch real usage.",
        help: ""
    )
    .environmentObject(mockViewModel([
        mockSnapshot(.cursor, name: "Cursor")
    ]))
    .frame(width: 640)
    .background(PadzyTheme.ground)
}

#Preview("Not found") {
    UserDefaults.standard.set(false, forKey: "previewAntigravityOff")
    return ConnectionRow(
        providerID: .antigravity,
        storageKey: "previewAntigravityOff",
        disclosure: "Reads live quota from the running Antigravity app on your Mac.",
        help: "Requires the Antigravity app to be open."
    )
    .environmentObject(mockViewModel([]))
    .frame(width: 640)
    .background(PadzyTheme.ground)
}
