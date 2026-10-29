import AppKit
import SwiftUI
import AIUsageDashboardCore

/// Where the dashboard window is: the tab, and the drill-in over it. Lives outside the view
/// so the menu bar's View and Go menus (⌘1/⌘2/⌘3, ⌘[) drive the same state the tab bar
/// and arrow keys do. The App observes it, which is what rebuilds the menus when Back
/// becomes available (SwiftUI `Commands` do not observe models themselves).
@MainActor
final class DashboardNavigator: ObservableObject {
    static let shared = DashboardNavigator()

    /// The pane on screen: a tab's own content or a provider drill-in.
    @Published private(set) var section: AppSection = .overview
    /// The tab a drill-in returns to, and the pane that stays rendered underneath one.
    /// Only a tab selection writes it, so drilling in and backing out is a round trip.
    @Published private(set) var homeTab: DashboardTab = .overview

    var canGoBack: Bool { section.isDrillIn }

    func select(_ tab: DashboardTab, viewModel: DashboardViewModel) {
        homeTab = tab
        navigate(to: tab.section)
        viewModel.showingSettings = false
    }

    func open(_ providerID: ProviderID, viewModel: DashboardViewModel) {
        viewModel.selectedProvider = providerID
        navigate(to: .provider(providerID))
        viewModel.showingSettings = false
    }

    /// Leaves a drill-in for the tab that owns the content behind it; no-op on a tab.
    func back(viewModel: DashboardViewModel) {
        guard canGoBack else { return }
        navigate(to: homeTab.section)
        viewModel.showingSettings = false
    }

    /// Single write point for `section`, so the drill-in transition animates in one place
    /// and is skipped under Reduce Motion (the pane swaps instantly instead of sliding).
    private func navigate(to destination: AppSection) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            section = destination
        } else {
            withAnimation(.easeOut(duration: 0.18)) { section = destination }
        }
    }
}

/// The dashboard's menu-bar commands. Every keyboard path the window has is also a menu
/// item, so it can be found and its shortcut learned there (mac-design "Keyboard first").
struct DashboardCommands: Commands {
    let navigator: DashboardNavigator
    let viewModel: DashboardViewModel
    /// Passed in from the App, which observes the navigator; read here it would go stale.
    let canGoBack: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(DashboardTab.allCases) { tab in
                Button(tab.label) {
                    showWindow()
                    navigator.select(tab, viewModel: viewModel)
                }
                .keyboardShortcut(tab.shortcutKey, modifiers: .command)
            }
            Divider()
            Button("Sync Now") {
                Task { await viewModel.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            Divider()
        }
        CommandMenu("Go") {
            Button("Back") { navigator.back(viewModel: viewModel) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!canGoBack)
        }
    }

    /// A tab chosen from the menu while the window is closed should open it.
    private func showWindow() {
        openWindow(id: DashboardWindow.id)
    }
}

enum DashboardWindow {
    static let id = "dashboard-window"
}
