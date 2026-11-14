import AppKit
import SwiftUI
import AIUsageDashboardCore

/// Where the dashboard window is: the tab, and the drill-in over it. Lives outside the view
/// so the menu bar's View and Go menus (⌘1 … ⌘4, ⌘[) drive the same state the tab bar
/// and arrow keys do. The App observes it, which is what rebuilds the menus when Back
/// becomes available (SwiftUI `Commands` do not observe models themselves).
@MainActor
final class DashboardNavigator: ObservableObject {
    static let shared = DashboardNavigator()

    /// The pane on screen: a tab's own content or a provider drill-in.
    @Published private(set) var section: AppSection = .overview {
        didSet { NavigationMenuState.shared.update(canGoBack: section.isDrillIn) }
    }
    /// The tab a drill-in returns to, and the pane that stays rendered underneath one.
    /// Only a tab selection writes it, so drilling in and backing out is a round trip.
    @Published private(set) var homeTab: DashboardTab = .overview

    var canGoBack: Bool { section.isDrillIn }

    func select(_ tab: DashboardTab, viewModel: DashboardViewModel) {
        navigate(to: tab.section, homeTab: tab)
        closeSettings(viewModel)
    }

    func open(_ providerID: ProviderID, viewModel: DashboardViewModel) {
        if viewModel.selectedProvider != providerID { viewModel.selectedProvider = providerID }
        navigate(to: .provider(providerID))
        closeSettings(viewModel)
    }

    /// Leaves a drill-in for the tab that owns the content behind it; no-op on a tab.
    func back(viewModel: DashboardViewModel) {
        guard canGoBack else { return }
        navigate(to: homeTab.section)
        closeSettings(viewModel)
    }

    /// Writes only when the drawer is open. A `@Published` write sends `objectWillChange` even
    /// when the value is unchanged, and every view model observer re-renders on it (WP-C AC 6:
    /// each tab switch used to redraw the menu bar item this way).
    private func closeSettings(_ viewModel: DashboardViewModel) {
        if viewModel.showingSettings { viewModel.showingSettings = false }
    }

    /// Single write point for `section` (and `homeTab` on a tab switch), so tab switches and
    /// drill-ins share one spring (`PadzyMotion.navigate`) and Reduce Motion swaps instantly.
    private func navigate(to destination: AppSection, homeTab tab: DashboardTab? = nil) {
        let apply = {
            if let tab { self.homeTab = tab }
            self.section = destination
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            apply()
        } else {
            withAnimation(PadzyMotion.navigate, apply)
        }
    }
}

/// The one navigation fact the menu bar's commands need: whether Go › Back applies. The App
/// observes this instead of the navigator, so a tab switch (which never changes it) does not
/// re-evaluate the App's scenes, the menu bar item's label among them (WP-C AC 6).
@MainActor
final class NavigationMenuState: ObservableObject {
    static let shared = NavigationMenuState()
    @Published private(set) var canGoBack = false

    func update(canGoBack value: Bool) {
        if canGoBack != value { canGoBack = value }
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
