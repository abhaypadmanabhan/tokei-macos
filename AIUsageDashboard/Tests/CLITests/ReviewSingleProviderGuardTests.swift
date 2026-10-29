import XCTest
@testable import AIUsageDashboardCore

final class ReviewSingleProviderGuardTests: XCTestCase {
    private func snapshot(age: TimeInterval = 0, confidence: String = "official") -> AgentSnapshot {
        let now = Date()
        let windows = [2.0, 40.0].map { used in
            AgentWindow(type: "monthly", usedPercent: used, resetsAt: now.addingTimeInterval(3_600),
                        confidence: confidence, source: "fixture", observedAt: now.addingTimeInterval(-age))
        } + [AgentWindow(type: "credits", usedPercent: 99, resetsAt: nil, confidence: "official",
                         source: "fixture", observedAt: now, bucketKey: "claude_extra_usage")]
        let provider = AgentProvider(id: "cursor", displayName: "Cursor", windows: windows,
                                     tokensToday: 0, lastUpdated: now)
        return AgentSnapshot(generatedAt: now, providers: [provider], aggregateUtilizationPercent: 40,
                             recommendation: AgentRecommendation(routeTo: "cursor", avoid: [], reason: "fixture",
                                                                 validUntil: now.addingTimeInterval(600)))
    }

    func testProviderOnlyDefaultAndExplicitUseHighestRateWindow() throws {
        for arguments in [["guard"], ["guard", "--provider", "cursor"]] {
            let output = try ReviewCLIProbe.run(arguments, snapshot: snapshot())
            XCTAssertEqual(output.status, 0)
            XCTAssertTrue(output.text.contains("headroom 60.0%"))
            XCTAssertEqual(output.text.split(separator: "\n").count, 1)
        }
        let below = try ReviewCLIProbe.run(["guard", "--min-headroom", "61"], snapshot: snapshot())
        XCTAssertEqual(below.status, 1)
    }

    func testProviderOnlyStaleAndUnconfirmedReadingsRemainUnavailable() throws {
        let stale = try ReviewCLIProbe.run(["guard"], snapshot: snapshot(age: 601))
        XCTAssertEqual(stale.status, 69)
        XCTAssertTrue(stale.text.contains("stale"))
        XCTAssertFalse(stale.text.contains("open Tokei"))
        let estimated = try ReviewCLIProbe.run(["guard"], snapshot: snapshot(confidence: "local_estimate"))
        XCTAssertEqual(estimated.status, 69)
    }
}
