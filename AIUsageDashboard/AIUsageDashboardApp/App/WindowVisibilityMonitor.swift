import SwiftUI
import AppKit

/// Tracks whether any of the app's windows are actually on screen, so live UI
/// (per-second countdown `TimelineView`s) can stop ticking when nothing is
/// visible.
///
/// The dashboard is a single SwiftUI `Window` scene, whose content view graph is
/// **retained when the window closes** (unlike `WindowGroup`). Without this gate,
/// every countdown `TimelineView` keeps its 1 Hz schedule alive and re-renders
/// the dashboard's ViewGraph forever — burning ~20% CPU as a background menu-bar
/// app even with no window open. `NSApplication.occlusionState` is the
/// system-sanctioned "is my work visible" signal: it drops `.visible` when all
/// windows are closed, hidden, minimized, or fully occluded, and regains it when
/// a window comes back to screen.
@MainActor
final class WindowVisibilityMonitor: ObservableObject {
    /// `true` when at least one app window is on screen (dashboard open, or the
    /// menu-bar popover showing). `false` when the app is idling in the menu bar.
    @Published private(set) var isVisible: Bool = true
    /// `true` only while the dashboard window itself is on screen. App-wide visibility is
    /// not enough for the dashboard: with only the menu-bar popover open the app counts as
    /// visible, and the closed dashboard's retained graph kept its 1 Hz clocks running
    /// (WP-C AC 4, 2026-11-15).
    @Published private(set) var dashboardOnScreen: Bool = true

    private var observer: NSObjectProtocol?
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification is delivered on the main queue; hop to the main
            // actor to satisfy isolation before touching @Published state.
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Any window's occlusion change, and the dashboard closing; each re-reads the
        // dashboard window's own state.
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                     NSWindow.didBecomeKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] note in
                let closing = note.name == NSWindow.willCloseNotification
                    && (note.object as? NSWindow)?.identifier?.rawValue == DashboardWindow.id
                MainActor.assumeIsolated { self?.refreshDashboard(closing: closing) }
            })
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func refresh() {
        #if DEBUG
        // A capture tour must not depend on other apps leaving the window uncovered: covered,
        // the dashboard drops to a plain fill and its proof hooks leave the view tree.
        // `-TokeiProofVisible YES` does the same for own-window captures and recordings, which
        // must not depend on what another app puts in front (captures run 2026-11-14 01:44:
        // a covered window captured as a plain fill).
        if ProofRoute.isTour || ProofRoute.forceVisible { isVisible = true; return }
        #endif
        isVisible = NSApp?.occlusionState.contains(.visible) ?? true
    }

    private func refreshDashboard(closing: Bool) {
        #if DEBUG
        if ProofRoute.isTour || ProofRoute.forceVisible { dashboardOnScreen = true; return }
        #endif
        let window = NSApp?.windows.first { $0.identifier?.rawValue == DashboardWindow.id }
        let onScreen = !closing && (window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
        if onScreen != dashboardOnScreen { dashboardOnScreen = onScreen }
    }
}

private struct DashboardVisibleKey: EnvironmentKey {
    /// Defaults to `true` so any view rendered without the monitor injected
    /// (previews, tests, incidental hosting) behaves exactly as before — live.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the app is currently visible on screen. Countdown timers read this
    /// to fall back to a static snapshot (no periodic schedule) when the app is
    /// idling in the menu bar. See ``WindowVisibilityMonitor``.
    var dashboardVisible: Bool {
        get { self[DashboardVisibleKey.self] }
        set { self[DashboardVisibleKey.self] = newValue }
    }
}
