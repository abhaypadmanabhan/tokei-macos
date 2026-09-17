import Combine
import SwiftUI
import AIUsageDashboardCore

/// Bottom status bar: a relative "Synced …" line and "Sync now". Path, confidence,
/// and the raw warning essay used to ride along (t04 D15) and are gone. The 1 Hz
/// clock is gated on window visibility (t02 F6) so a hidden dashboard does not
/// mutate status state.
struct DashboardStatusStrip: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.dashboardVisible) private var dashboardVisible

    @State private var countdownTick = Date()
    private let countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            statusRow
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(PadzyTheme.statusBar)
        }
        .onAppear { applyTick(Date()) }
        .onReceive(countdownTimer) { date in
            applyTick(date)
        }
    }

    private func applyTick(_ date: Date) {
        guard let applied = StatusStripTickGate.appliedDate(date, dashboardVisible: dashboardVisible) else { return }
        countdownTick = applied
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
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Sync now")
    }

    private var syncStatusText: String {
        if viewModel.isLoading { return "Syncing…" }
        guard let syncedRelative else { return "Not synced yet" }
        return "Synced \(syncedRelative)"
    }

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
}
