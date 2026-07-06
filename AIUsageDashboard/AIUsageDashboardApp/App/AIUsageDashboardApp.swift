import SwiftUI
import AIUsageDashboardCore

@main
struct AIUsageDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        Window("AI Usage Dashboard", id: "dashboard-window") {
            DashboardView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
        } label: {
            let total = viewModel.claudeSnapshot?.todayUsage.totalTokens ?? 0
            Text("⌾ \(TokenFormatter.format(total))")
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

