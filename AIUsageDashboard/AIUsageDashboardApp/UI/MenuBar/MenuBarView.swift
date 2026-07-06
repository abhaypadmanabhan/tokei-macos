import SwiftUI
import AIUsageDashboardCore

struct MenuBarView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.snapshots) { snapshot in
                HStack {
                    Text(snapshot.displayName)
                    Spacer()
                    ConfidenceBadge(confidence: snapshot.todayUsage.confidence)
                }
                Text("Today: \(snapshot.todayUsage.totalTokens ?? 0) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Open Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
        .task {
            await viewModel.refresh()
        }
    }
}

