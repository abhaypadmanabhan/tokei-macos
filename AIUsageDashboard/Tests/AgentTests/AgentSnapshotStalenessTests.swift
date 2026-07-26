import XCTest
@testable import AIUsageDashboardCore

final class AgentSnapshotStalenessTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(generatedAt: Date) -> AgentSnapshot {
        AgentSnapshot(
            generatedAt: generatedAt,
            providers: [],
            aggregateUtilizationPercent: nil,
            recommendation: nil
        )
    }

    func testFreshSnapshotIsNotStale() {
        let snap = snapshot(generatedAt: base)
        let now = base.addingTimeInterval(30) // 30s old, threshold 600s
        XCTAssertFalse(snap.isStale(asOf: now))
        XCTAssertEqual(snap.age(asOf: now), 30)

        let stamped = snap.withStaleness(asOf: now)
        XCTAssertEqual(stamped.stale, false)
        XCTAssertEqual(stamped.ageSeconds, 30)
    }

    func testOldSnapshotIsStale() {
        let snap = snapshot(generatedAt: base)
        let now = base.addingTimeInterval(2 * 3600) // 2h old
        XCTAssertTrue(snap.isStale(asOf: now))

        let stamped = snap.withStaleness(asOf: now)
        XCTAssertEqual(stamped.stale, true)
        XCTAssertEqual(stamped.ageSeconds, 7200)
    }

    func testBoundaryIsExclusive() {
        let snap = snapshot(generatedAt: base)
        // Exactly at the threshold is NOT stale; one second past is.
        let atThreshold = base.addingTimeInterval(AgentSnapshot.stalenessThreshold)
        let pastThreshold = base.addingTimeInterval(AgentSnapshot.stalenessThreshold + 1)
        XCTAssertFalse(snap.isStale(asOf: atThreshold))
        XCTAssertTrue(snap.isStale(asOf: pastThreshold))
    }

    func testFutureGeneratedAtClampsToZeroAge() {
        // Clock skew putting the write in the future must not read as "fresh forever"
        // via a negative age — it clamps to 0 and is not stale.
        let snap = snapshot(generatedAt: base.addingTimeInterval(500))
        let now = base
        XCTAssertEqual(snap.age(asOf: now), 0)
        XCTAssertFalse(snap.isStale(asOf: now))
        XCTAssertEqual(snap.withStaleness(asOf: now).ageSeconds, 0)
    }

    func testDefaultFileURLUsesAppSupportSubdir() {
        let url = AgentSnapshot.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, "agent-snapshot.json")
        XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent == "AIUsageDashboard")
    }
}
