import XCTest
@testable import AIUsageDashboardCore

final class ForecastForwardCompatibilityTests: XCTestCase {
    func testUnknownForecastKindDoesNotRejectTheSnapshot() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(AgentSnapshotFixtures.full.utf8)) as? [String: Any])
        var providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        var windows = try XCTUnwrap(providers[0]["windows"] as? [[String: Any]])
        windows[0]["forecast"] = ["kind": "futureProjection"]
        providers[0]["windows"] = windows
        root["providers"] = providers
        let snapshot = try AgentSnapshot.makeDecoder().decode(
            AgentSnapshot.self, from: JSONSerialization.data(withJSONObject: root)
        )
        let encoded = try AgentSnapshot.makeEncoder().encode(snapshot)
        let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let rows = try XCTUnwrap(roundTrip["providers"] as? [[String: Any]])
        let readings = try XCTUnwrap(rows[0]["windows"] as? [[String: Any]])
        let forecast = try XCTUnwrap(readings[0]["forecast"] as? [String: String])
        XCTAssertEqual(forecast["kind"], "futureProjection")
    }
}
