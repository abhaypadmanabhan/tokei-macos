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
/// `provider.<ProviderID raw value>` and `provider.<raw>.scrolled`.
enum ProofRoute {
    static let popoverWindowID = "proof-popover"

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
        guard let route else { return }
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
