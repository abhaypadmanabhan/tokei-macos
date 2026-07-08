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
}
