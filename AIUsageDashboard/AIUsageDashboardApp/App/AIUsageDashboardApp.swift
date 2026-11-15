import SwiftUI
import AIUsageDashboardCore
import Sparkle

@main
struct AIUsageDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowVisibility = WindowVisibilityMonitor()
    /// Observed here so the Go menu rebuilds when Back becomes available. Only that fact: the
    /// navigator itself changes on every tab switch (see `NavigationMenuState`).
    @ObservedObject private var menuState = NavigationMenuState.shared

    init() {
        UserDefaults.standard.register(defaults: CodexProvider.liveQuotaDefaults)
        // Toggles that are on until turned off: Gemini's network usage, and predictive quota
        // warnings (§4 contract 4). Registering keeps every reader on the same default.
        UserDefaults.standard.register(defaults: ProviderMetadata.networkDefaultsOn)
        UserDefaults.standard.register(defaults: [AlertSettings.predictiveWarningsKey: true])
        // Burn nudges are on until turned off (Abhay 2026-11-14; contract `BurnNudgePolicy`).
        UserDefaults.standard.register(defaults: [BurnNudgePolicy.enabledKey: true])
        #if DEBUG
        // Before any view reads a preference: the demo's fixed settings win for this run.
        if DemoFixture.isActive { DemoFixture.installDefaults() }
        #endif
    }

    var body: some Scene {
        Window("Tokei", id: DashboardWindow.id) {
            DashboardView()
                .environmentObject(appDelegate.viewModel)
                .environment(appDelegate.burnBoard)
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
                navigator: DashboardNavigator.shared,
                viewModel: appDelegate.viewModel,
                canGoBack: menuState.canGoBack
            )
        }

        #if DEBUG
        // Debug builds only: the popover's content in a plain window, so it can be captured
        // without clicking the status item (`-TokeiProofRoute popover`).
        Window("Menu bar popover", id: ProofRoute.popoverWindowID) {
            MenuBarView()
                .environmentObject(appDelegate.viewModel)
                .environment(appDelegate.burnBoard)
        }
        .windowResizability(.contentSize)
        #endif

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.viewModel)
                .environment(appDelegate.burnBoard)
                .environment(\.dashboardVisible, windowVisibility.isVisible)
        } label: {
            MenuBarLabel(model: appDelegate.menuBarLabelModel)
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
    let viewModel: DashboardViewModel = {
        #if DEBUG
        if DemoFixture.isActive { return DemoFixture.viewModel() }
        #endif
        return DashboardViewModel()
    }()
    /// The burn surfaces' model: follows `viewModel.burn` and holds the pending celebration.
    private(set) lazy var burnBoard = BurnBoard(viewModel: viewModel)
    /// The status item's label values, narrowed from `viewModel` (see `MenuBarLabelModel`).
    private(set) lazy var menuBarLabelModel = MenuBarLabelModel(viewModel: viewModel)

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
        if PerformanceProbe.isEnabled {
            // The benchmark uses a disposable bundle identity as well as a synthetic
            // Foundation home. Refuse to run a probe against the installed app's state.
            let home = FileManager.default.homeDirectoryForCurrentUser
            guard Bundle.main.bundleIdentifier?.hasPrefix("ai.padzy.tokei.perf.") == true,
                  FileManager.default.fileExists(atPath: home.appendingPathComponent(".tokei-perf-home").path)
            else { fatalError("perf-bench requires a disposable bundle and synthetic home") }
            PerformanceProbe.emit("isolated", fields: ["home": home.path])
            Task { @MainActor in
                // Observe the first actual window, then close it: the CPU sample must
                // measure the ordinary menu-bar-only app, including its retained views.
                while let app = NSApp {
                    if let window = app.windows.first(where: { $0.isVisible && $0.frame.width > 300 }) {
                        PerformanceProbe.emit("first_window")
                        window.close()
                        PerformanceProbe.emit("window_closed")
                        break
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        } else {
            _ = updater // force-instantiate so Sparkle's scheduled background checks start
        }
        #if DEBUG
        // The demo data set replaces every real source (`DemoFixture.viewModel()`): no
        // first-run seed, no saved store; the one sync reads only the demo providers.
        if DemoFixture.isActive {
            Task {
                await viewModel.refresh()
                ProofRoute.apply(navigator: .shared, viewModel: viewModel)
            }
            return
        }
        #endif
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
            PerformanceProbe.emit("initial_refresh_complete")
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}
