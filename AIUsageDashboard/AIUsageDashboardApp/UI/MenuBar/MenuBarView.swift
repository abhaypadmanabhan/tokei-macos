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

                if activeSnapshots.isEmpty {
                    Text("NO ACTIVE PROVIDERS")
                        .font(.mono(size: 11))
                        .foregroundColor(PadzyTheme.muted)
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
        .task {
            viewModel.beginAutoSync()
            if viewModel.lastSyncedAt == nil {
                await viewModel.refresh()
            }
        }
    }
}
