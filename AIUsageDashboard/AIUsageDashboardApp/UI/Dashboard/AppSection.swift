import SwiftUI
import AIUsageDashboardCore

/// The four top-level destinations the right pane routes between. Held as local
/// `@State` in `DashboardView`; `Core` stays untouched. `.settings` is mirrored
/// into `viewModel.showingSettings` so no existing Core consumer breaks.
enum AppSection: Equatable {
    case overview
    case provider(ProviderID)
    case settings
    case connections
}

// MARK: - Stubs (replaced by later tasks)

/// TASK 1 STUB — Task 4 replaces this with the real guided Connections list
/// (`UI/Connections/ConnectionsView.swift`). Delete this stub when it lands.
struct ConnectionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialKicker(number: "00", title: "CONNECTIONS")
                .padding(.horizontal, 28)
                .padding(.top, 24)
            Text("connections")
                .font(.mono(size: 12))
                .foregroundColor(PadzyTheme.muted)
                .padding(.horizontal, 28)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
