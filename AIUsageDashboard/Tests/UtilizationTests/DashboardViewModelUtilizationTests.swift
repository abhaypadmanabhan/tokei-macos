import XCTest
@testable import AIUsageDashboardCore

@MainActor
final class DashboardViewModelUtilizationTests: XCTestCase {
    private func snapshotWithWindow(_ providerID: ProviderID, used: Double) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            quotaWindows: [
                QuotaWindow(providerID: providerID, type: .monthly, used: used, limit: 100,
                            confidence: .providerReported, source: "test")
            ],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
    }

    func testUtilizationDerivedFromSnapshots() {
        let vm = DashboardViewModel()
        vm.snapshots = [snapshotWithWindow(.cursor, used: 40)]
        XCTAssertEqual(vm.utilization.count, 1)
        XCTAssertEqual(vm.utilization.first?.usedPercent, 40)
        XCTAssertEqual(vm.utilization.first?.providerID, .cursor)
    }

    func testAggregateUtilizationTodayDerivedFromSnapshots() {
        let vm = DashboardViewModel()
        vm.snapshots = [snapshotWithWindow(.cursor, used: 40)]
        XCTAssertEqual(vm.aggregateUtilizationToday, 40)
        XCTAssertEqual(vm.aggregateUtilization?.coveredProviders, [.cursor])
    }

    func testEmptyWhenNoSnapshots() {
        let vm = DashboardViewModel()
        XCTAssertTrue(vm.utilization.isEmpty)
        XCTAssertNil(vm.aggregateUtilizationToday)
        XCTAssertNil(vm.aggregateUtilization)
    }

    func testDoesNotMutateSnapshots() {
        // The accessor is purely derived — reading it leaves published state intact.
        let vm = DashboardViewModel()
        let snaps = [snapshotWithWindow(.cursor, used: 40)]
        vm.snapshots = snaps
        _ = vm.utilization
        _ = vm.aggregateUtilizationToday
        XCTAssertEqual(vm.snapshots.count, 1)
        XCTAssertEqual(vm.snapshots.first?.providerID, .cursor)
    }

    // MARK: - Pace accessors

    private static let paceNow = Date(timeIntervalSince1970: 1_000_000)

    private func paceSnapshot(_ providerID: ProviderID, windows: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            quotaWindows: windows,
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
    }

    private func paceWindow(
        _ providerID: ProviderID, _ type: QuotaWindowType, used: Double,
        resetIn: TimeInterval, duration: TimeInterval? = nil
    ) -> QuotaWindow {
        QuotaWindow(providerID: providerID, type: type, used: used, limit: 100,
                    resetAt: Self.paceNow.addingTimeInterval(resetIn),
                    confidence: .providerReported, source: "test", windowDuration: duration)
    }

    func testPaceForUtilizationUsesSourceWindowDuration() throws {
        // A monthly window has no implied length; the reported 30 d gives it one.
        let model = DashboardViewModel(now: { Self.paceNow })
        model.snapshots = [paceSnapshot(.cursor, windows: [
            paceWindow(.cursor, .monthly, used: 10, resetIn: 15 * 86_400, duration: 30 * 86_400)
        ])]
        let util = try XCTUnwrap(model.utilization.first)
        let pace = try XCTUnwrap(model.pace(for: util))
        XCTAssertEqual(pace.elapsedPercent, 50, accuracy: 1e-9)
        XCTAssertEqual(pace.state, .behind)
    }

    func testPaceForUtilizationNilWithoutLength() throws {
        let model = DashboardViewModel(now: { Self.paceNow })
        model.snapshots = [paceSnapshot(.cursor, windows: [
            paceWindow(.cursor, .monthly, used: 10, resetIn: 15 * 86_400)
        ])]
        let util = try XCTUnwrap(model.utilization.first)
        XCTAssertNil(model.pace(for: util), "no reported length and no implied one: show nothing")
    }

    func testPaceNilForRemainingOnlyReadings() throws {
        // The gauge can show 30% from limit - remaining, but pace needs a reported used.
        let model = DashboardViewModel(now: { Self.paceNow })
        let remainingOnly = QuotaWindow(
            providerID: .cursor, type: .weekly, used: nil, limit: 100, remaining: 70,
            resetAt: Self.paceNow.addingTimeInterval(7 * 86_400 / 2),
            confidence: .providerReported, source: "test"
        )
        model.snapshots = [paceSnapshot(.cursor, windows: [remainingOnly])]
        let util = try XCTUnwrap(model.utilization.first)
        XCTAssertEqual(util.usedPercent, 30, accuracy: 1e-9)
        XCTAssertNil(model.pace(for: util))
        XCTAssertNil(model.tightestAccountPace)
    }

    func testTightestAccountPaceFollowsTightestWindow() throws {
        // Claude's weekly (80%) is tighter than its 5 h (20%) and Codex (30%).
        let model = DashboardViewModel(now: { Self.paceNow })
        model.snapshots = [
            paceSnapshot(.claudeCode, windows: [
                paceWindow(.claudeCode, .fiveHour, used: 20, resetIn: 4 * 3_600),
                paceWindow(.claudeCode, .weekly, used: 80, resetIn: 7 * 86_400 / 2)
            ]),
            paceSnapshot(.codex, windows: [paceWindow(.codex, .weekly, used: 30, resetIn: 86_400)])
        ]
        XCTAssertEqual(model.tightestAccountPressure?.usedPercent, 80)
        let pace = try XCTUnwrap(model.tightestAccountPace)
        XCTAssertEqual(pace.elapsedPercent, 50, accuracy: 1e-9)
        XCTAssertEqual(pace.state, .ahead)
    }

    func testTightestAccountPaceNilWhenNoQuota() {
        let model = DashboardViewModel(now: { Self.paceNow })
        XCTAssertNil(model.tightestAccountPace)
    }
}
