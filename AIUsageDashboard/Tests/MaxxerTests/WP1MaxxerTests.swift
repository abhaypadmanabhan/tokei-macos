import XCTest
@testable import AIUsageDashboardCore

final class WP1MaxxerTests: XCTestCase {
    func testTwoModelsOneHourFastAndUnpricedAreKeptDistinct() throws {
        let now = Date()
        let day = Calendar.current.startOfDay(for: now)
        let suite = "ai.padzy.tokei.wp1.maxxer"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plans = MaxxerPlanCostStore(defaults: defaults)
        let snapshot = ProviderSnapshot(providerID: .claudeCode, displayName: "Claude", authStatus: .unknown,
                                        todayUsage: .unavailable, weekUsage: .unavailable,
                                        dailyModelUsage: [day: [
                                            "claude-sonnet-4-6": TokenUsage(cacheCreationTokens: 1_000_000,
                                                cacheCreation1hTokens: 600_000, confidence: .localParsed),
                                            "claude-opus-5-5@fast": TokenUsage(inputTokens: 1_000_000,
                                                confidence: .localParsed),
                                            "unknown-model": TokenUsage(inputTokens: 123, confidence: .localParsed)
                                        ]])
        let value = try XCTUnwrap(MaxxerValueEngine.scorecard(snapshots: [snapshot], planCosts: plans,
                                                            now: now).providers.first)
        // Sonnet writes: $1.50 + $3.60; fast Opus input: $8.00. Unknown stays nil.
        XCTAssertEqual(try XCTUnwrap(value.apiEquivalentUSD), 13.1, accuracy: 0.000001)
        XCTAssertTrue(value.hasUnpricedTokens)
        XCTAssertNil(value.models.first { $0.model == "unknown-model" }?.apiEquivalentUSD)
    }
    func testMissingHistoryDoesNotInventAZeroDollarValue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ai.padzy.tokei.wp1.maxxer.empty"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let antigravity = AntigravityProvider(stateDatabaseURL: directory.appendingPathComponent("missing-state"),
                                             conversationParser: .init(roots: []), userDefaults: defaults)
        let copilot = CopilotProvider(installationMarkers: [], extensionDirectories: [],
                                      sessionParser: .init(sessionStateDirectory: directory))
        let snapshots = try await [antigravity.fetchSnapshot(), copilot.fetchSnapshot()]
        let scorecard = MaxxerValueEngine.scorecard(snapshots: snapshots,
            planCosts: MaxxerPlanCostStore(defaults: defaults), now: Date())
        for snapshot in snapshots { XCTAssertNil(snapshot.dailyModelUsage) }
        for value in scorecard.providers { XCTAssertNil(value.apiEquivalentUSD) }
    }

}
