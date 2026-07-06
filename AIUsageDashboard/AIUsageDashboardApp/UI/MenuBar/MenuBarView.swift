import SwiftUI
import AIUsageDashboardCore

struct MenuBarView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialKicker(number: "01", title: "PROVIDERS")

            VStack(alignment: .leading, spacing: 6) {
                let activeSnapshots = ProviderID.allCases.compactMap { providerID -> ProviderSnapshot? in
                    guard viewModel.isAvailable(providerID), let snapshot = viewModel.snapshot(for: providerID) else { return nil }
                    return snapshot
                }

                if let errorMessage = viewModel.errorMessage {
                    SurfaceStateView(
                        kind: .error(headline: "Sync failed", detail: errorMessage),
                        compact: true,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                } else if activeSnapshots.isEmpty && viewModel.isLoading {
                    SurfaceStateView(kind: .loading(message: "Syncing"), compact: true)
                } else if activeSnapshots.isEmpty {
                    SurfaceStateView(
                        kind: .empty(
                            headline: "No active providers",
                            hint: "Run an AI CLI, then it shows up here."
                        ),
                        compact: true
                    )
                } else {
                    ForEach(activeSnapshots) { snapshot in
                        HStack {
                            Text(snapshot.displayName.uppercased())
                                .font(.mono(size: 11))
                                .foregroundColor(PadzyTheme.muted)
                            Spacer()
                            HStack(spacing: 8) {
                                if snapshot.providerID == .codex,
                                   let sessionWindow = snapshot.quotaWindows.first(where: { $0.type == .session }),
                                   let used = sessionWindow.used {
                                    Text("S \(Int(round(used)))%")
                                        .font(.mono(size: 10))
                                        .foregroundColor(PadzyTheme.muted)
                                }
                                Text(TokenFormatter.format(snapshot.todayUsage.totalTokens))
                                    .font(.mono(size: 11))
                                    .foregroundColor(PadzyTheme.ink)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(PadzyTheme.surface)
            .border(PadzyTheme.muted.opacity(0.3), width: 1)

            HairlineDivider()

            HStack {
                if let date = viewModel.lastSyncedAt {
                    Text("SYNCED: \(timeFormatter.string(from: date))")
                        .font(.mono(size: 9))
                        .foregroundColor(PadzyTheme.muted)
                } else {
                    Text("SYNCED: NEVER")
                        .font(.mono(size: 9))
                        .foregroundColor(PadzyTheme.muted)
                }
                Spacer()
            }

            HairlineDivider()

            VStack(spacing: 8) {
                // Open Dashboard - Single primary action uses the accent color
                Button(action: {
                    openWindow(id: "dashboard-window")
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Text("OPEN DASHBOARD")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .border(PadzyTheme.accent, width: 1)
                }
                .buttonStyle(.plain)

                // Settings — opens the in-app Settings pane inside the dashboard window
                // (there is no separate Settings dialog; a menu-bar-extra app has no ⌘, menu).
                Button(action: {
                    viewModel.showingSettings = true
                    openWindow(id: "dashboard-window")
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Text("SETTINGS")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .border(PadzyTheme.muted, width: 1)
                }
                .buttonStyle(.plain)

                // Quit
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Text("QUIT")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .border(PadzyTheme.muted, width: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 250)
        .background(PadzyTheme.ground)
        .preferredColorScheme(.dark)
        .task {
            viewModel.beginAutoSync()
            if viewModel.lastSyncedAt == nil {
                await viewModel.refresh()
            }
        }
    }
}
