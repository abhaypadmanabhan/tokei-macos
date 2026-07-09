import SwiftUI
import AIUsageDashboardCore

/// The four top-level destinations the right pane routes between. Held as local
/// `@State` in `DashboardView`; `Core` stays untouched.
///
/// This local state is the source of truth for navigation. `viewModel.showingSettings`
/// is reconciled in one direction each way, not a true two-way binding: selecting a
/// section writes the flag (`true` only for `.settings`, `false` otherwise), and an
/// external RISING edge of the flag (e.g. the menu-bar Settings action) routes the
/// pane to `.settings`. Clearing the flag never changes the section.
enum AppSection: Equatable {
    case overview
    case provider(ProviderID)
    case settings
    case connections
}
