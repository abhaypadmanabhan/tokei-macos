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

    private var observer: NSObjectProtocol?

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
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        isVisible = NSApp?.occlusionState.contains(.visible) ?? true
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
