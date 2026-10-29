#if DEBUG
import AppKit
import SwiftUI
import AIUsageDashboardCore

/// Debug builds only (never compiled into Release): launch arguments that open one screen
/// for an own-window capture, and a menu self-test (mac-verify "snapshot launch mode" and
/// "self-test"). Arguments arrive through the argument domain of `UserDefaults`:
///
///     Tokei -TokeiProofRoute overview.quota -TokeiProofRange 30
///     Tokei -TokeiSelfTest menus        # prints PASS/FAIL per check, exits 0 or 1
///
/// Routes: `overview.usage`, `overview.quota`, `value`, `agents`, `settings`, `popover`,
/// `provider.<ProviderID raw value>` and `provider.<raw>.scrolled`. `-TokeiProofFixture
/// extraUsage` adds Claude's extra-usage window (see `injectExtraUsage`).
enum ProofRoute {
    static let popoverWindowID = "proof-popover"
    static let metricNotification = Notification.Name("TokeiProof.metric")
    static let scrollNotification = Notification.Name("TokeiProof.scroll")
    static let popoverNotification = Notification.Name("TokeiProof.popover")

    static var route: String? { UserDefaults.standard.string(forKey: "TokeiProofRoute") }

    static var wantsQuotaLens: Bool { route == "overview.quota" }
    static var wantsPopover: Bool { route == "popover" }
    static var scrollsDrillIn: Bool { route?.hasSuffix(".scrolled") == true }

    @MainActor
    static func apply(navigator: DashboardNavigator, viewModel: DashboardViewModel) {
        switch UserDefaults.standard.integer(forKey: "TokeiProofRange") {
        case 30: viewModel.range = .thirtyDay
        case 90: viewModel.range = .ninetyDay
        default: break
        }
        if UserDefaults.standard.string(forKey: "TokeiSelfTest") == "menus" {
            Task { await runMenuSelfTest(navigator: navigator, viewModel: viewModel) }
            return
        }
        if UserDefaults.standard.string(forKey: "TokeiProofFixture") == "extraUsage" {
            injectExtraUsage(into: viewModel)
        }
        if let directory = UserDefaults.standard.string(forKey: "TokeiProofTour") {
            Task { await runTour(markerDirectory: directory, navigator: navigator, viewModel: viewModel) }
            return
        }
        if let route { open(route, navigator: navigator, viewModel: viewModel) }
    }

    // MARK: Tour

    /// `-TokeiProofTour <dir>`: after the first live sync lands, walks every WP-3 surface,
    /// writing `<dir>/step.txt` ("<n> <name> <window title>") when each has settled, so an
    /// outside script can capture this app's own window; then writes "done" and quits.
    /// One stop on the tour: what to show, and the title of the window that shows it.
    private struct TourStep {
        let name: String
        var window = "Tokei"
        let show: () -> Void
    }

    @MainActor
    private static func runTour(
        markerDirectory: String,
        navigator: DashboardNavigator,
        viewModel: DashboardViewModel
    ) async {
        let marker = URL(fileURLWithPath: markerDirectory).appendingPathComponent("step.txt")
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
        func post(_ name: Notification.Name, _ object: String? = nil) {
            NotificationCenter.default.post(name: name, object: object)
        }
        var waited = 0.0
        let awaitingLive = { viewModel.showingSavedSnapshots || viewModel.isLoading || viewModel.lastSyncedAt == nil }
        while awaitingLive() && waited < 300 {
            await pause(0.5)
            waited += 0.5
        }
        let steps = [
            TourStep(name: "03-overview-usage-7d") {
                navigator.select(.overview, viewModel: viewModel)
                viewModel.range = .sevenDay
                post(metricNotification, "usage")
            },
            TourStep(name: "04-overview-usage-30d") { viewModel.range = .thirtyDay },
            TourStep(name: "05-overview-quota") {
                viewModel.range = .sevenDay
                post(metricNotification, "quota")
            },
            TourStep(name: "06-claude-drillin-top") {
                injectExtraUsage(into: viewModel)
                navigator.open(.claudeCode, viewModel: viewModel)
            },
            TourStep(name: "07-claude-drillin-scrolled") {
                injectExtraUsage(into: viewModel)
                post(scrollNotification)
            },
            TourStep(name: "08-value") {
                injectExtraUsage(into: viewModel)
                navigator.select(.value, viewModel: viewModel)
            },
            TourStep(name: "09-settings") { viewModel.showingSettings = true },
            TourStep(name: "10-menubar-popover", window: "Menu bar popover") {
                viewModel.showingSettings = false
                post(popoverNotification)
            }
        ]
        for (index, step) in steps.enumerated() {
            step.show()
            await pause(2.5)
            try? "\(index + 1) \(step.name) \(step.window)\n".write(to: marker, atomically: true, encoding: .utf8)
            await pause(3.0)
        }
        try? "done\n".write(to: marker, atomically: true, encoding: .utf8)
        await pause(1.0)
        exit(0)
    }

    @MainActor
    private static func open(_ route: String, navigator: DashboardNavigator, viewModel: DashboardViewModel) {
        switch route {
        case "value": navigator.select(.value, viewModel: viewModel)
        case "agents": navigator.select(.agents, viewModel: viewModel)
        case "settings": viewModel.showingSettings = true
        default:
            let parts = route.split(separator: ".")
            if parts.first == "provider", parts.count >= 2, let id = ProviderID(rawValue: String(parts[1])) {
                navigator.open(id, viewModel: viewModel)
            }
        }
    }

    // MARK: Fixtures

    /// `-TokeiProofFixture extraUsage`: adds the §4.3 window from the saved real response
    /// (`tasks/research/claude-usage-response.json`: 2152 of 5000 minor USD, disabled,
    /// out_of_credits) to Claude, so the row can be captured before the network lane lands
    /// it. The first live sync replaces it.
    @MainActor
    private static func injectExtraUsage(into viewModel: DashboardViewModel) {
        viewModel.snapshots = viewModel.snapshots.map { snapshot in
            guard snapshot.providerID == .claudeCode else { return snapshot }
            let extra = QuotaWindow(
                providerID: .claudeCode, type: .credits, used: 21.52, limit: 50, remaining: 28.48,
                confidence: .providerReported,
                source: "api.anthropic.com/api/oauth/usage extra_usage disabled out_of_credits (proof fixture)",
                label: "Extra usage", bucketKey: ExtraUsageCopy.bucketKey
            )
            return ProviderSnapshot(
                providerID: snapshot.providerID, displayName: snapshot.displayName,
                authStatus: snapshot.authStatus, quotaWindows: snapshot.quotaWindows + [extra],
                todayUsage: snapshot.todayUsage, weekUsage: snapshot.weekUsage,
                monthUsage: snapshot.monthUsage, lifetimeUsage: snapshot.lifetimeUsage,
                costUsage: snapshot.costUsage, warnings: snapshot.warnings,
                lastSyncedAt: snapshot.lastSyncedAt, dailyTotals: snapshot.dailyTotals,
                hourlyTotals: snapshot.hourlyTotals, dailyModelUsage: snapshot.dailyModelUsage,
                accounts: snapshot.accounts, headlineAccountID: snapshot.headlineAccountID
            )
        }
    }

    // MARK: Menu self-test

    /// Checks every dashboard shortcut is a menu item with the right key, then fires the
    /// shortcuts through the main menu the way a key press does and reads where the window
    /// went. Prints one PASS/FAIL line per check and exits 0 only when all pass.
    @MainActor
    private static func runMenuSelfTest(navigator: DashboardNavigator, viewModel: DashboardViewModel) async {
        setvbuf(stdout, nil, _IOLBF, 0)
        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            print("\(passed ? "PASS" : "FAIL") \(name)")
            if !passed { failures += 1 }
        }
        func settle() async { try? await Task.sleep(nanoseconds: 600_000_000) }
        await settle()
        let dashboard = NSApp.windows.first { $0.identifier?.rawValue == DashboardWindow.id }
        print("INFO app active=\(NSApp.isActive) window key=\(dashboard?.isKeyWindow ?? false)"
            + " visible=\(NSApp.occlusionState.contains(.visible))")

        let commandMap: [MenuCommand] = [
            MenuCommand(menu: "View", title: "Overview", key: "1"),
            MenuCommand(menu: "View", title: "Value", key: "2"),
            MenuCommand(menu: "View", title: "Agents", key: "3"),
            MenuCommand(menu: "View", title: "Sync Now", key: "r"),
            MenuCommand(menu: "Go", title: "Back", key: "[")
        ]
        for command in commandMap {
            let found = menuItem(command.menu, command.title)
            check(
                "\(command.menu) › \(command.title) is ⌘\(command.key.uppercased())",
                found?.keyEquivalent == command.key && found?.keyEquivalentModifierMask == .command
            )
        }

        check("Go › Back is disabled on a tab", menuItem("Go", "Back")?.isEnabled == false)
        press("2", keyCode: 19)
        await settle()
        check("⌘2 shows Value", navigator.homeTab == .value && navigator.section == .value)

        // Drill in, then press ⌘[ before anything opens or reads the Go menu: the shortcut
        // must work straight from the keyboard.
        navigator.open(.claudeCode, viewModel: viewModel)
        await settle()
        press("[", keyCode: 33)
        await settle()
        check("⌘[ returns to Value", navigator.section == .value)
        navigator.open(.claudeCode, viewModel: viewModel)
        await settle()
        check("Go › Back is enabled in a drill-in", menuItem("Go", "Back")?.isEnabled == true)
        navigator.back(viewModel: viewModel)

        press("3", keyCode: 20)
        await settle()
        check("⌘3 shows Agents", navigator.section == .connections)
        press("1", keyCode: 18)
        await settle()
        check("⌘1 shows Overview", navigator.section == .overview)

        print(failures == 0 ? "SELFTEST PASS" : "SELFTEST FAIL (\(failures))")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    /// One row of the command map: a menu item and its ⌘ key.
    private struct MenuCommand {
        let menu: String
        let title: String
        let key: String
    }

    /// Reads an item the way a person sees it: SwiftUI applies an item's enabled state when
    /// the menu is about to show (`menuNeedsUpdate`), not when the model changes.
    @MainActor
    private static func menuItem(_ menu: String, _ title: String) -> NSMenuItem? {
        let submenu = NSApp.mainMenu?.item(withTitle: menu)?.submenu
        if let submenu { submenu.delegate?.menuNeedsUpdate?(submenu) }
        return submenu?.item(withTitle: title)
    }

    /// Posts ⌘<key> through `NSApp.sendEvent`, the path a real key press takes (key window,
    /// then the main menu's key equivalents), to the dashboard window.
    @MainActor
    private static func press(_ key: String, keyCode: UInt16) {
        let window = NSApp.windows.first { $0.identifier?.rawValue == DashboardWindow.id }
        window?.makeKeyAndOrderFront(nil)
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode
        ) else { return }
        NSApp.sendEvent(event)
    }
}
#endif
