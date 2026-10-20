import SwiftUI
import AIUsageDashboardCore
import Sparkle

@main
struct AIUsageDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowVisibility = WindowVisibilityMonitor()

    init() {
        UserDefaults.standard.register(defaults: CodexProvider.liveQuotaDefaults)
    }

    var body: some Scene {
        Window("Tokei", id: "dashboard-window") {
            DashboardView()
                .environmentObject(appDelegate.viewModel)
                .environment(\.dashboardVisible, windowVisibility.isVisible)
        }
        .windowStyle(.titleBar)
        // Free-resize down to the DashboardView's 640×480 minimum (and up to
        // full-screen); the status strip reflows responsively so nothing clips.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    AppDelegate.shared?.checkForUpdates()
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.viewModel)
                .environment(\.dashboardVisible, windowVisibility.isVisible)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)
        // Settings live in-app (dashboard right pane via the sidebar SETTINGS entry),
        // not in a separate macOS Settings window.
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    /// Owned here, not by a view: syncing starts when the app finishes launching, even
    /// when neither the dashboard window nor the menu-bar popover is ever shown (a hidden
    /// launch, e.g. `open -j` or a login item set to hide). Views only read it.
    let viewModel = DashboardViewModel()

    // Feed URL + EdDSA key live in Info.plist (SUFeedURL/SUPublicEDKey); checks
    // are background-only unless an update exists or checkForUpdates() is called.
    private(set) lazy var updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updater // force-instantiate so Sparkle's scheduled background checks start
        viewModel.beginAutoSync()
        Task { await viewModel.refresh() }
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}

