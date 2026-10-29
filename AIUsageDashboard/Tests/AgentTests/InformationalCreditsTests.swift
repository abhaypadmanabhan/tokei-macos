import XCTest
@testable import AIUsageDashboardCore

final class InformationalCreditsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(providerID: ProviderID = .claudeCode, extraOnly: Bool = false) -> ProviderSnapshot {
        let weekly = QuotaWindow(providerID: providerID, type: .weekly, used: 8, limit: 100,
                                 resetAt: now.addingTimeInterval(3_600), confidence: .providerReported,
                                 source: "fixture", observedAt: now)
        let extra = QuotaWindow(providerID: providerID, type: .credits, used: 49.5, limit: 50,
                                confidence: .providerReported, source: "fixture disabled",
                                bucketKey: "claude_extra_usage", observedAt: now)
        return ProviderSnapshot(providerID: providerID, displayName: "Fixture", authStatus: .authenticated,
                                quotaWindows: extraOnly ? [extra] : [weekly, extra],
                                todayUsage: .unavailable, weekUsage: .unavailable)
    }

    func testExtraUsageDoesNotChangeUtilizationOrSnapshotAggregate() {
        let value = snapshot()
        XCTAssertEqual(UtilizationEngine.utilizations(from: [value]).map(\.usedPercent), [8])
        XCTAssertEqual(UtilizationEngine.aggregate(from: [value])?.usedPercent, 8)
        XCTAssertEqual(AgentSnapshotWriter.buildSnapshot(from: [value], generatedAt: now).aggregateUtilizationPercent, 8)
    }

    func testExtraUsageNeverFiresOrArmsThresholdAlerts() {
        let result = ThresholdEvaluator.evaluate(snapshots: [snapshot()], clock: FixedCreditsClock(date: now),
                                                 previouslyFired: [])
        XCTAssertTrue(result.notifications.isEmpty)
        XCTAssertTrue(result.fired.isEmpty)
    }

    func testExtraOnlyProviderDoesNotLowerAggregateCoverage() {
        let result = UtilizationEngine.aggregate(from: [snapshot(), snapshot(providerID: .codex, extraOnly: true)])
        XCTAssertEqual(result?.usedPercent, 8)
        XCTAssertEqual(result?.coverage, .complete)
    }
}

private struct FixedCreditsClock: Clock {
    let date: Date
    func now() -> Date { date }
}
