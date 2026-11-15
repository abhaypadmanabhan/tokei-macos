import XCTest
@testable import AIUsageDashboardCore

/// WP-C AC 4: the status strip's 1 Hz clock runs only while the dashboard is on screen.
@MainActor
final class SecondTickerTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testAHiddenDashboardHasNoTimerAndNothingFires() {
        let ticker = SecondTicker(interval: 0.05)
        ticker.setVisible(false)
        spin(0.4)
        XCTAssertFalse(ticker.isRunning)
        XCTAssertEqual(ticker.fires, 0)
    }

    func testItTicksWhileVisibleAndStopsTheMomentItHides() {
        let ticker = SecondTicker(interval: 0.05)
        ticker.setVisible(true)
        spin(0.4)
        XCTAssertTrue(ticker.isRunning)
        XCTAssertGreaterThanOrEqual(ticker.fires, 3)

        ticker.setVisible(false)
        let firedWhileVisible = ticker.fires
        spin(0.4)
        XCTAssertFalse(ticker.isRunning)
        XCTAssertEqual(ticker.fires, firedWhileVisible, "a hidden dashboard must not wake the app")
    }

    func testShowingAgainCatchesUpAtOnceAndNeverStacksTimers() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let ticker = SecondTicker(interval: 0.05, clock: { clock })
        ticker.setVisible(true)
        ticker.setVisible(false)
        clock = Date(timeIntervalSince1970: 5_000)
        ticker.setVisible(true)
        XCTAssertEqual(ticker.now, clock, "the strip shows the current time the moment it reappears")
        ticker.setVisible(true)
        spin(0.3)
        XCTAssertLessThanOrEqual(ticker.fires, 8, "a second setVisible(true) must not add a second timer")
        ticker.setVisible(false)
    }
}
