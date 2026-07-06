import SwiftUI

@main
struct AIUsageDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .windowStyle(.titleBar)

        MenuBarExtra("AI Usage Dashboard", systemImage: "chart.bar") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Additional app lifecycle setup can go here.
    }
}

