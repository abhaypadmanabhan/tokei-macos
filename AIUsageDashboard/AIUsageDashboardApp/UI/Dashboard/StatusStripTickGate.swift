import Combine
import Foundation

/// F6: a status-strip tick records a date only while the dashboard window is visible.
enum StatusStripTickGate {
    static func appliedDate(_ date: Date, dashboardVisible: Bool) -> Date? {
        dashboardVisible ? date : nil
    }
}

/// The status strip's once-a-second clock, which exists only while the dashboard is on
/// screen. A `Timer.publish(…).autoconnect()` in the view fired every second for the
/// app's whole life, hidden or not, and only its effect was gated (WP-C AC 4, 2026-11-15):
/// here, hidden means there is no timer at all, so nothing wakes the app.
@MainActor
final class SecondTicker: ObservableObject {
    @Published private(set) var now: Date
    /// How many times the timer has fired, for tests and the Debug tick report.
    private(set) var fires = 0
    var isRunning: Bool { timer != nil }

    private var timer: Timer?
    private let clock: () -> Date
    private let interval: TimeInterval

    init(interval: TimeInterval = 1, clock: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.clock = clock
        now = clock()
    }

    /// Starts the clock when the dashboard shows (catching up at once) and stops it when
    /// it hides. Idempotent.
    func setVisible(_ visible: Bool) {
        guard visible else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        now = clock()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    #if DEBUG
    /// Every strip clock's fires in this process, for `-TokeiProofTickReport`.
    static var processFires = 0
    #endif

    private func tick() {
        fires += 1
        #if DEBUG
        Self.processFires += 1
        #endif
        if let applied = StatusStripTickGate.appliedDate(clock(), dashboardVisible: true) { now = applied }
    }

    deinit { timer?.invalidate() }
}
