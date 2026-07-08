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
