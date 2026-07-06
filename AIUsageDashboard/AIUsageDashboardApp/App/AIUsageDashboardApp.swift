import SwiftUI
import AIUsageDashboardCore

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

        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
        } label: {
            HStack(spacing: 5) {
                Image(nsImage: TokeiMark.menuBarImage)
                Text(TokenFormatter.format(viewModel.claudeSnapshot?.todayUsage.totalTokens ?? 0))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Additional app lifecycle setup can go here.
    }
}

