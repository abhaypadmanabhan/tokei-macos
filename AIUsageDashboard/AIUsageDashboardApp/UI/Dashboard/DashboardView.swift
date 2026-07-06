import SwiftUI
import AIUsageDashboardCore

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.snapshots) { snapshot in
                NavigationLink(destination: ProviderDetailView(snapshot: snapshot)) {
                    ProviderCard(snapshot: snapshot)
                }
            }
            .navigationTitle("AI Usage Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await viewModel.refresh()
        }
    }
}

