import SwiftUI
import AIUsageDashboardCore
import Sparkle

@main
struct AIUsageDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        Window("Tokei", id: "dashboard-window") {
            DashboardView()
                .environmentObject(viewModel)
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
                .environmentObject(viewModel)
        } label: {
            HStack(spacing: 5) {
                Image(nsImage: TokeiMark.menuBarImage)
                Text(TokenFormatter.format(viewModel.menuBarTodayTotal))
            }
        }
        .menuBarExtraStyle(.window)
        // Settings live in-app (dashboard right pane via the sidebar SETTINGS entry),
        // not in a separate macOS Settings window.
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

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
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}

