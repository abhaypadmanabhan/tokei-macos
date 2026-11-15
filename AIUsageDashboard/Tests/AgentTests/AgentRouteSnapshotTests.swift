import XCTest
@testable import AIUsageDashboardCore

final class AgentRouteSnapshotTests: XCTestCase {
    func testRouteBlockIsAdditiveAndSurvivesRecommendationExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = QuotaWindow(providerID: .codex, type: .fiveHour, used: 40, limit: 100,
                                  resetAt: now.addingTimeInterval(600), confidence: .providerReported,
                                  source: "fixture", observedAt: now)
        let provider = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                        quotaWindows: [window], todayUsage: .unavailable, weekUsage: .unavailable)
        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
        let route = try XCTUnwrap(snapshot.route)
        XCTAssertEqual(route.generatedAt, now)
        XCTAssertEqual(route.rows.first?.provider, "codex")
        XCTAssertEqual(route.rows.first?.remainingPercent, 60)
        let data = try AgentSnapshot.makeEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["providers"])
        XCTAssertNotNil(object["burn"])
        XCTAssertNotNil(object["route"])
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.withRecommendationValidity(asOf: now.addingTimeInterval(601)).route, route)
        var old = object
        old.removeValue(forKey: "route")
        let legacy = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.route)
        XCTAssertEqual(legacy.providers, snapshot.providers)
    }
}
