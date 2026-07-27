import SwiftUI
import AIUsageDashboardCore

/// The dashboard's bottom status bar: a live sync dot, a relative "Synced …" line, the
/// today-usage confidence, the watched path, and a trailing "Sync now" — plus the
/// non-info warning sub-banner that rides above it.
///
/// Lifted out of `DashboardView` as its own view because it owns state nothing else in
/// the shell reads: the once-a-second `countdownTick` that keeps the relative time
/// honest, and the pulse opacity for the in-flight dot. Keeping that timer inside the
/// strip means the rest of the shell no longer re-evaluates every second either.
///
/// Reads the same `DashboardViewModel` from the environment; it holds no state of its
/// own beyond those two animation/tick values.
struct DashboardStatusStrip: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseOpacity: Double = 1.0
    @State private var countdownTick = Date()
    private let countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var selectedSnapshot: ProviderSnapshot? {
        viewModel.snapshot(for: viewModel.selectedProvider)
    }

    /// Reflows toward the 640pt minimum by dropping the confidence first, then the path —
    /// the dot, the status line, and Sync now always stay so nothing critical clips.
    var body: some View {
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
        .onReceive(countdownTimer) { _ in
            countdownTick = Date()
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

    private func refresh() {
        Task { await viewModel.refresh() }
    }

    private var syncButton: some View {
        Button(action: refresh) {
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
}
