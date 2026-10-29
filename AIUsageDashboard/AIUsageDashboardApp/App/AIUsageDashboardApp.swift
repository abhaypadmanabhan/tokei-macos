import SwiftUI
import AIUsageDashboardCore
import Sparkle

@main
struct AIUsageDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowVisibility = WindowVisibilityMonitor()
    /// Observed here so the View and Go menus rebuild when Back becomes available.
    @ObservedObject private var navigator = DashboardNavigator.shared

    init() {
        UserDefaults.standard.register(defaults: CodexProvider.liveQuotaDefaults)
        // Toggles that are on until turned off: Gemini's network usage, and predictive quota
        // warnings (§4 contract 4). Registering keeps every reader on the same default.
        UserDefaults.standard.register(defaults: ProviderMetadata.networkDefaultsOn)
        UserDefaults.standard.register(defaults: [AlertSettings.predictiveWarningsKey: true])
    }

    var body: some Scene {
        Window("Tokei", id: DashboardWindow.id) {
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
            DashboardCommands(
                navigator: navigator,
                viewModel: appDelegate.viewModel,
                canGoBack: navigator.canGoBack
            )
        }

        #if DEBUG
        // Debug builds only: the popover's content in a plain window, so it can be captured
        // without clicking the status item (`-TokeiProofRoute popover`).
        Window("Menu bar popover", id: ProofRoute.popoverWindowID) {
            MenuBarView()
                .environmentObject(appDelegate.viewModel)
        }
        .windowResizability(.contentSize)
        #endif

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
        // Order matters: the first-run seed treats "no usage store yet" as a fresh install,
        // and the first sync writes that store.
        AddAgentModel.seedOnFirstLaunchIfNeeded()
        // The last run's numbers go on screen first (a cold live sync reads every log and
        // took 66 s on 2026-10-28), labelled as saved until the live sync replaces them.
        Task {
            await viewModel.loadSavedSnapshots()
            #if DEBUG
            ProofRoute.apply(navigator: .shared, viewModel: viewModel)
            #endif
            viewModel.beginAutoSync()
            await viewModel.refresh()
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}
