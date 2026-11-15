import Combine
import SwiftUI
import AIUsageDashboardCore

/// Bottom status bar: a relative "Synced …" line and "Sync now". Path, confidence,
/// and the raw warning essay used to ride along (t04 D15) and are gone. The 1 Hz
/// clock (`SecondTicker`) exists only while the dashboard window is on screen (t02 F6,
/// WP-C AC 4), so a hidden dashboard neither changes state nor wakes the app.
struct DashboardStatusStrip: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.dashboardVisible) private var dashboardVisible

    @StateObject private var ticker = SecondTicker()

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            statusRow
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(PadzyTheme.statusBar)
        }
        .onAppear { ticker.setVisible(dashboardVisible) }
        .onChange(of: dashboardVisible) { _, visible in ticker.setVisible(visible) }
        .onDisappear { ticker.setVisible(false) }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Text(syncStatusText)
                .font(.sans(size: 15))
                .foregroundColor(PadzyTheme.ink3)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 8)

            syncButton
        }
    }

    private func refresh() {
        Task { await viewModel.refresh() }
    }

    private var syncButton: some View {
        Button(action: refresh) {
            Text("Sync now")
                .font(.sans(size: 15, weight: .semibold))
                .foregroundColor(viewModel.isLoading ? PadzyTheme.ink5 : PadzyTheme.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ⌘R lives on View › Sync Now, so the shortcut is listed in the menu bar.
        .help("Sync now (⌘R)")
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Sync now")
    }

    private var syncStatusText: String {
        // Saved numbers from the last run are on screen: say how old they are.
        if viewModel.showingSavedSnapshots {
            _ = ticker.now
            return SavedAgeCopy.statusLine(
                savedAt: viewModel.savedSnapshotsDate, updating: viewModel.isLoading, now: Date()
            )
        }
        if viewModel.isLoading { return "Syncing…" }
        guard let syncedRelative else { return "Not synced yet" }
        return "Synced \(syncedRelative)"
    }

    private var syncedRelative: String? {
        _ = ticker.now
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
}
