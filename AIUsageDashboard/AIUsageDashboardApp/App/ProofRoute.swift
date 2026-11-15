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
/// Routes: `overview.usage`, `overview.quota`, `burn`, `burn.share` (the share sheet over Burn),
/// `burn.middle` and `burn.bottom` (the Burn tab scrolled to its lower sections),
/// `value`, `agents`, `settings`, `popover`, `provider.<ProviderID raw value>` and
/// `provider.<raw>.scrolled`. Burn state flags (`-TokeiBurnSample`, `-TokeiBurnEmpty`,
/// `-TokeiBurnMoment`) live in `BurnDebug`; `-TokeiShareCardOut <path>` writes the card PNG. `-TokeiProofFixture
/// extraUsage` adds Claude's extra-usage window (see `injectExtraUsage`); the tour also
/// re-keys one Claude model as a fast-tier key (see `injectFastTierModel`). `-TokeiProofFixture demo`
/// replaces every real source with `DemoFixture` (publishable captures);
/// `-TokeiProofWindowSize <w>x<h>` fixes the dashboard's size.
enum ProofRoute {
    static let popoverWindowID = "proof-popover"
    static let metricNotification = Notification.Name("TokeiProof.metric")
    static let scrollNotification = Notification.Name("TokeiProof.scroll")
    static let popoverNotification = Notification.Name("TokeiProof.popover")

    static var route: String? { UserDefaults.standard.string(forKey: "TokeiProofRoute") }

    static var wantsQuotaLens: Bool { route == "overview.quota" }
    static var isTour: Bool { UserDefaults.standard.string(forKey: "TokeiProofTour") != nil }
    static var wantsPopover: Bool { route == "popover" }
    static var wantsShareSheet: Bool { route == "burn.share" }
    /// Keeps the window's content live while covered, for own-window captures.
    static var forceVisible: Bool { UserDefaults.standard.bool(forKey: "TokeiProofVisible") }
    /// `burn.middle` (left on the table, tier) and `burn.bottom` (badges): where the Burn tab
    /// scrolls to for a capture of its lower sections.
    static var burnScrollAnchor: String? {
        route == "burn.middle" || route == "burn.bottom" ? route : nil
    }
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
        if let size = UserDefaults.standard.string(forKey: "TokeiProofWindowSize") { sizeDashboard(size) }
        if let path = UserDefaults.standard.string(forKey: "TokeiProofTickReport") {
            Task { await reportTicks(to: path) }
        }
    }

    /// `-TokeiProofTickReport <file>` (with `-TokeiProofRoute popover`, without
    /// `-TokeiProofVisible`): counts the status strip's clock fires while the dashboard is
    /// on screen, while it is ordered out with only the popover open, and after it comes
    /// back; writes one line per phase to <file>, then quits (WP-C AC 4).
    @MainActor
    private static func reportTicks(to path: String) async {
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
        func dashboard() -> NSWindow? { NSApp.windows.first { $0.identifier?.rawValue == DashboardWindow.id } }
        var lines: [String] = []
        func phase(_ name: String, seconds: Double) async {
            let start = SecondTicker.processFires
            await pause(seconds)
            let popover = NSApp.windows.contains { $0.identifier?.rawValue == popoverWindowID && $0.isVisible }
            lines.append("\(name) seconds=\(Int(seconds)) fires=\(SecondTicker.processFires - start)"
                + " dashboardVisible=\(dashboard()?.isVisible ?? false) popoverOpen=\(popover)"
                + " appVisible=\(NSApp.occlusionState.contains(.visible))")
        }
        await pause(3)
        dashboard()?.makeKeyAndOrderFront(nil)
        await phase("dashboard-open", seconds: 5)
        dashboard()?.orderOut(nil)
        await phase("dashboard-hidden-popover-open", seconds: 10)
        dashboard()?.makeKeyAndOrderFront(nil)
        await phase("dashboard-back", seconds: 5)
        dashboard()?.performClose(nil)
        await phase("dashboard-closed", seconds: 5)
        dashboard()?.makeKeyAndOrderFront(nil)
        await phase("dashboard-reopened", seconds: 5)
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// `-TokeiProofWindowSize 1100x760`: the dashboard's content size for captures, so every
    /// picture of one screen has the same frame whatever size the window last had.
    @MainActor
    private static func sizeDashboard(_ value: String) {
        let parts = value.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == DashboardWindow.id }) else { return }
            window.setContentSize(NSSize(width: parts[0], height: parts[1]))
            window.center()
            // A pointer resting over the window would put a hover readout in the capture:
            // slide the window to whichever side of the screen the pointer is not on.
            if let screen = window.screen?.visibleFrame, window.frame.contains(NSEvent.mouseLocation) {
                let x = NSEvent.mouseLocation.x > screen.midX ? screen.minX : screen.maxX - window.frame.width
                window.setFrameOrigin(NSPoint(x: x, y: window.frame.minY))
            }
            // Key and active, so the capture shows live traffic lights and full-strength text.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Tour

    /// `-TokeiProofTour <dir>`: after the first live sync lands, walks every WP-3 surface,
    /// writing `<dir>/step.txt` ("<n> <name> <window title>") when each has settled, so an
    /// outside script can capture this app's own window; then writes "done" and quits.
    /// One stop on the tour: what to show, and the title of the window that shows it.
    private struct TourStep {
        let name: String
        var window = "Tokei"
        /// Run again just before the capture: a live sync during the step replaces snapshots
        /// and with them any injected fixture (tour run 2026-10-29: Value lost its extra usage).
        var keep: () -> Void = {}
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
        var waited = 0.0
        let awaitingLive = { viewModel.showingSavedSnapshots || viewModel.isLoading || viewModel.lastSyncedAt == nil }
        while awaitingLive() && waited < 600 {
            await pause(0.5)
            waited += 0.5
        }
        let steps = tourSteps(navigator: navigator, viewModel: viewModel)
        for (index, step) in steps.enumerated() {
            bringDashboardForward()
            await pause(0.8)
            step.show()
            await pause(2.5)
            step.keep()
            await pause(0.6)
            try? "\(index + 1) \(step.name) \(step.window)\n".write(to: marker, atomically: true, encoding: .utf8)
            await pause(3.0)
        }
        try? "done\n".write(to: marker, atomically: true, encoding: .utf8)
        await pause(1.0)
        exit(0)
    }

    /// Every stop on the tour, in capture order.
    @MainActor
    private static func tourSteps(navigator: DashboardNavigator, viewModel: DashboardViewModel) -> [TourStep] {
        func post(_ name: Notification.Name, _ object: String? = nil) {
            NotificationCenter.default.post(name: name, object: object)
        }
        return [
            TourStep(name: "02-after-live-sync") { navigator.select(.overview, viewModel: viewModel) },
            TourStep(name: "03-overview-usage-7d") {
                viewModel.range = .sevenDay
                post(metricNotification, "usage")
            },
            TourStep(name: "04-overview-usage-30d") { viewModel.range = .thirtyDay },
            TourStep(name: "05-overview-cost-7d") {
                viewModel.range = .sevenDay
                post(metricNotification, "cost")
            },
            TourStep(name: "06-overview-cost-30d") { viewModel.range = .thirtyDay },
            TourStep(name: "07-overview-quota") {
                viewModel.range = .sevenDay
                post(metricNotification, "quota")
            },
            TourStep(name: "08-claude-drillin-top", keep: { injectExtraUsage(into: viewModel) }, show: {
                injectExtraUsage(into: viewModel)
                navigator.open(.claudeCode, viewModel: viewModel)
            }),
            TourStep(name: "09-claude-drillin-scrolled", keep: {
                injectExtraUsage(into: viewModel)
                injectFastTierModel(into: viewModel)
            }, show: {
                injectExtraUsage(into: viewModel)
                injectFastTierModel(into: viewModel)
                post(scrollNotification)
            }),
            TourStep(name: "10-burn") { navigator.select(.burn, viewModel: viewModel) },
            TourStep(name: "11-value", keep: { injectExtraUsage(into: viewModel) }, show: {
                injectExtraUsage(into: viewModel)
                navigator.select(.value, viewModel: viewModel)
            }),
            TourStep(name: "12-settings") { viewModel.showingSettings = true },
            TourStep(name: "13-menubar-popover", window: "Menu bar popover") {
                viewModel.showingSettings = false
                post(popoverNotification)
            }
        ]
    }

    /// Another app can cover the window during the long wait for the live sync. Covered, the
    /// dashboard draws a plain fill and its proof hooks leave the view tree (tour run
    /// 2026-10-29: steps 02-09 blank, no popover), so each stop first brings it forward, and
    /// during a tour `WindowVisibilityMonitor` reports the window visible regardless.
    @MainActor
    private static func bringDashboardForward() {
        NSApp.activate()
        let window = NSApp.windows.first { $0.identifier?.rawValue == DashboardWindow.id }
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    @MainActor
    private static func open(_ route: String, navigator: DashboardNavigator, viewModel: DashboardViewModel) {
        switch route {
        case "burn", "burn.share", "burn.middle", "burn.bottom": navigator.select(.burn, viewModel: viewModel)
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
        check("⌘2 shows Burn", navigator.homeTab == .burn && navigator.section == .burn)
        press("3", keyCode: 20)
        await settle()
        check("⌘3 shows Value", navigator.homeTab == .value && navigator.section == .value)

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

        press("4", keyCode: 21)
        await settle()
        check("⌘4 shows Agents", navigator.section == .connections)
        navigator.open(.claudeCode, viewModel: viewModel)
        await settle()
        press("\u{1b}", keyCode: 53, modifiers: [])
        await settle()
        check("Esc returns to Agents", navigator.section == .connections)
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

    private static let commandMap: [MenuCommand] = [
        MenuCommand(menu: "View", title: "Overview", key: "1"),
        MenuCommand(menu: "View", title: "Burn", key: "2"),
        MenuCommand(menu: "View", title: "Value", key: "3"),
        MenuCommand(menu: "View", title: "Agents", key: "4"),
        MenuCommand(menu: "View", title: "Sync Now", key: "r"),
        MenuCommand(menu: "Go", title: "Back", key: "[")
    ]

    /// Reads an item the way a person sees it: SwiftUI applies an item's enabled state when
    /// the menu is about to show (`menuNeedsUpdate`), not when the model changes.
    @MainActor
    private static func menuItem(_ menu: String, _ title: String) -> NSMenuItem? {
        let submenu = NSApp.mainMenu?.item(withTitle: menu)?.submenu
        if let submenu { submenu.delegate?.menuNeedsUpdate?(submenu) }
        return submenu?.item(withTitle: title)
    }

    /// Posts ⌘<key> (or a bare key) through `NSApp.sendEvent`, the path a real key press
    /// takes (key window, then the main menu's key equivalents), to the dashboard window.
    @MainActor
    private static func press(_ key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = .command) {
        let window = NSApp.windows.first { $0.identifier?.rawValue == DashboardWindow.id }
        window?.makeKeyAndOrderFront(nil)
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode
        ) else { return }
        NSApp.sendEvent(event)
    }
}

extension ProofRoute {
    // MARK: Fixtures

    /// `-TokeiProofFixture extraUsage`: adds the §4.3 window from the saved real response
    /// (`tasks/research/claude-usage-response.json`: 2152 of 5000 minor USD, disabled,
    /// out_of_credits) to Claude, so the row can be captured before the network lane lands
    /// it. Adds it once; the first live sync replaces it.
    @MainActor
    private static func injectExtraUsage(into viewModel: DashboardViewModel) {
        viewModel.snapshots = viewModel.snapshots.map { snapshot in
            guard snapshot.providerID == .claudeCode, ExtraUsageCopy.window(in: snapshot) == nil else {
                return snapshot
            }
            let extra = QuotaWindow(
                providerID: .claudeCode, type: .credits, used: 21.52, limit: 50, remaining: 28.48,
                confidence: .providerReported,
                source: "api.anthropic.com/api/oauth/usage extra_usage disabled out_of_credits (proof fixture)",
                label: "Extra usage", bucketKey: ExtraUsageCopy.bucketKey
            )
            return replacing(snapshot, quotaWindows: snapshot.quotaWindows + [extra])
        }
    }

    /// Re-keys this month's least-used Claude model the way WP-1 stores fast-mode tokens
    /// (`<model>@fast`), so "Value by model" can be captured showing the base name and the
    /// tier word before WP-1 lands. This branch has no `@fast` rate, so that row reads "no
    /// public rate". Once only; the first live sync replaces it.
    @MainActor
    private static func injectFastTierModel(into viewModel: DashboardViewModel) {
        viewModel.snapshots = viewModel.snapshots.map { snapshot in
            guard snapshot.providerID == .claudeCode, let days = snapshot.dailyModelUsage else { return snapshot }
            let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? .distantPast
            var tokens: [String: Int] = [:]
            for (day, models) in days where day >= monthStart {
                for (model, usage) in models { tokens[model, default: 0] += usage.totalTokens ?? 0 }
            }
            guard !tokens.keys.contains(where: { ModelKeyName($0).tier != nil }),
                  let least = tokens.min(by: { $0.value < $1.value })?.key else { return snapshot }
            let rekeyed = days.mapValues { models in
                Dictionary(uniqueKeysWithValues: models.map { ($0.key == least ? least + "@fast" : $0.key, $0.value) })
            }
            return replacing(snapshot, dailyModelUsage: rekeyed)
        }
    }

    private static func replacing(
        _ snapshot: ProviderSnapshot,
        quotaWindows: [QuotaWindow]? = nil,
        dailyModelUsage: [Date: [String: TokenUsage]]? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: snapshot.providerID, displayName: snapshot.displayName,
            authStatus: snapshot.authStatus, quotaWindows: quotaWindows ?? snapshot.quotaWindows,
            todayUsage: snapshot.todayUsage, weekUsage: snapshot.weekUsage,
            monthUsage: snapshot.monthUsage, lifetimeUsage: snapshot.lifetimeUsage,
            costUsage: snapshot.costUsage, warnings: snapshot.warnings,
            lastSyncedAt: snapshot.lastSyncedAt, dailyTotals: snapshot.dailyTotals,
            hourlyTotals: snapshot.hourlyTotals, dailyModelUsage: dailyModelUsage ?? snapshot.dailyModelUsage,
            accounts: snapshot.accounts, headlineAccountID: snapshot.headlineAccountID
        )
    }
}
#endif
