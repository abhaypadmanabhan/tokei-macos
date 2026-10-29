import XCTest
@testable import AIUsageDashboardCore

final class SnapshotForecastTests: XCTestCase {
    func testOtherForecastKindsAndCreditsHaveNoPace() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        struct ForecastCase {
            let used: Double
            let seconds: TimeInterval
            let kind: String
        }
        let cases = [ForecastCase(used: 0, seconds: 9_000, kind: "lastsToReset"),
                     ForecastCase(used: 100, seconds: 9_000, kind: "exhausted"),
                     ForecastCase(used: 5, seconds: 17_900, kind: "tooEarly")]
        for item in cases {
            let window = QuotaWindow(providerID: .claudeCode, type: .session, used: item.used, limit: 100,
                                     resetAt: now.addingTimeInterval(item.seconds), confidence: .providerReported,
                                     source: "fixture")
            let provider = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude",
                                            authStatus: .authenticated, quotaWindows: [window],
                                            todayUsage: .unavailable, weekUsage: .unavailable)
            let result = AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
            XCTAssertEqual(result.providers.first?.windows.first?.forecast?.kind, item.kind)
        }
        let credit = QuotaWindow(providerID: .claudeCode, type: .credits, used: 49.5, limit: 50,
                                 confidence: .providerReported, source: "fixture", bucketKey: "claude_extra_usage")
        let provider = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude", authStatus: .authenticated,
                                        quotaWindows: [credit], todayUsage: .unavailable, weekUsage: .unavailable)
        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
        let window = snapshot.providers.first?.windows.first
        XCTAssertNil(window?.pace)
        XCTAssertNil(window?.forecast)
    }

    func testSnapshotWriterUsesPrivateModes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = AgentSnapshotWriter(directory: directory)
        let success = await writer.write(from: [])
        XCTAssertTrue(success)
        let location = directory.appendingPathComponent("agent-snapshot.json")
        let file = try FileManager.default.attributesOfItem(atPath: location.path)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual(file[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(folder[.posixPermissions] as? Int, 0o700)
    }

    func testSnapshotPublishesHandCalculatedPaceAndForecast() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Five hours total, half elapsed, 80% used: remaining 20% lasts 2,250 seconds.
        let window = QuotaWindow(providerID: .codex, type: .session, used: 80, limit: 100,
                                 resetAt: now.addingTimeInterval(9_000), confidence: .providerReported,
                                 source: "fixture", observedAt: now)
        let provider = ProviderSnapshot(providerID: .codex, displayName: "Codex", authStatus: .authenticated,
                                        quotaWindows: [window], todayUsage: .unavailable, weekUsage: .unavailable)
        let snapshot = AgentSnapshotWriter.buildSnapshot(from: [provider], generatedAt: now)
        let data = try AgentSnapshot.makeEncoder().encode(snapshot)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let providers = try XCTUnwrap(root["providers"] as? [[String: Any]])
        let windows = try XCTUnwrap(providers.first?["windows"] as? [[String: Any]])
        let encoded = try XCTUnwrap(windows.first)
        XCTAssertEqual(encoded["windowSeconds"] as? Double, 18_000)
        let pace = try XCTUnwrap(encoded["pace"] as? [String: Any])
        XCTAssertEqual(pace["state"] as? String, "ahead")
        XCTAssertEqual(pace["elapsedPercent"] as? Double, 50)
        XCTAssertEqual(pace["deltaPoints"] as? Double, 30)
        let forecast = try XCTUnwrap(encoded["forecast"] as? [String: Any])
        XCTAssertEqual(forecast["kind"] as? String, "runsOut")
        XCTAssertEqual(forecast["runsOutAt"] as? String,
                       ISO8601DateFormatter().string(from: now.addingTimeInterval(2_250)))
    }
}
