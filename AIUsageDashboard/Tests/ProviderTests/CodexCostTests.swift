import XCTest
@testable import AIUsageDashboardCore

final class CodexCostTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func codexDirectory() -> URL {
        tempDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    private func writeSession(_ content: String, codex: URL, name: String = "rollout-test.jsonl") throws {
        let sessionDir = codex
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("07", isDirectory: true)
            .appendingPathComponent("06", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try content.write(to: sessionDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: - CodexPricing.estimateCost

    func testEstimateCostForKnownModelMatchesExpectedDollarsWithinEpsilon() {
        let tokens = TokenUsage(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 200_000,
            reasoningTokens: 100_000,
            confidence: .localParsed
        )

        let amount = CodexPricing.estimateCost(tokens: tokens, model: "gpt-4.1")
        // input: 1,000,000 * 2.00 = 2.00
        // cached: 200,000 * 0.50 = 0.10
        // output+reasoning: 600,000 * 8.00 = 4.80
        // total = 6.90
        XCTAssertNotNil(amount)
        XCTAssertEqual(amount!, 6.90, accuracy: 0.0001)
    }

    func testEstimateCostForUnknownFamilyReturnsNil() {
        // A future *major* with no base row in the table resolves to no rate — never a guess.
        let tokens = TokenUsage(inputTokens: 100, outputTokens: 50, confidence: .localParsed)
        XCTAssertNil(CodexPricing.estimateCost(tokens: tokens, model: "gpt-6-ultra"))
        XCTAssertNil(CodexPricing.estimateCost(tokens: tokens, model: "some-other-model"))
    }

    func testEstimateCostPricesNewMinorUnderBaseFamilyRate() {
        // gpt-5.5 / gpt-5.4 / gpt-5.3-codex are newer than the table → priced under gpt-5.
        let tokens = TokenUsage(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 200_000,
            reasoningTokens: 100_000,
            confidence: .localParsed
        )
        let base = CodexPricing.estimateCost(tokens: tokens, model: "gpt-5")
        XCTAssertNotNil(base)
        for slug in ["gpt-5.5", "gpt-5.4", "gpt-5.3-codex", "GPT-5.5"] {
            let amount = CodexPricing.estimateCost(tokens: tokens, model: slug)
            XCTAssertNotNil(amount, "expected family fallback for \(slug)")
            XCTAssertEqual(amount!, base!, accuracy: 0.0001, "\(slug) should price under gpt-5 base rate")
        }
        // An exact table row must still win over the family fallback.
        XCTAssertNotEqual(
            CodexPricing.estimateCost(tokens: tokens, model: "gpt-5-mini")!,
            base!,
            accuracy: 0.0001
        )
    }

    // MARK: - CodexProvider.fetchSnapshot() costUsage attachment

    func testFetchSnapshotAttachesEstimatedCostForKnownModel() async throws {
        let codex = codexDirectory()
        try writeSession(CodexFixtures.sessionWithModel(model: "gpt-4.1"), codex: codex)

        let provider = CodexProvider(codexDirectory: codex)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNotNil(snapshot.costUsage)
        XCTAssertEqual(snapshot.costUsage?.currency, "USD")
        XCTAssertEqual(snapshot.costUsage?.confidence, .estimated)
        XCTAssertNotNil(snapshot.costUsage?.amount)
        XCTAssertGreaterThan(snapshot.costUsage!.amount!, 0)
    }

    func testFetchSnapshotEstimatesCostForNewMinorViaFamilyFallback() async throws {
        // Real-world case on this machine: Codex logs report gpt-5.5, newer than the
        // table. It must now price under the gpt-5 base rate rather than show nothing.
        let codex = codexDirectory()
        try writeSession(CodexFixtures.sessionWithModel(model: "gpt-5.5"), codex: codex)

        let provider = CodexProvider(codexDirectory: codex)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNotNil(snapshot.costUsage?.amount)
        XCTAssertEqual(snapshot.costUsage?.confidence, .estimated)
        XCTAssertEqual(snapshot.costUsage?.currency, "USD")
    }

    func testFetchSnapshotOmitsCostForUnknownFamily() async throws {
        let codex = codexDirectory()
        try writeSession(CodexFixtures.sessionWithModel(model: "gpt-6-ultra"), codex: codex)

        let provider = CodexProvider(codexDirectory: codex)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.costUsage?.amount)
        XCTAssertEqual(snapshot.costUsage?.confidence, .unavailable)
    }

    func testFetchSnapshotOmitsCostWhenNoModelInfoFound() async throws {
        let codex = codexDirectory()
        try writeSession(CodexFixtures.twoTokenCountEvents(), codex: codex)

        let provider = CodexProvider(codexDirectory: codex)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.costUsage?.amount)
        XCTAssertEqual(snapshot.costUsage?.confidence, .unavailable)
    }

    func testFetchSnapshotWithNoLogsDoesNotCrash() async throws {
        let codex = codexDirectory()
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)

        let provider = CodexProvider(codexDirectory: codex)
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertNil(snapshot.costUsage?.amount)
        XCTAssertEqual(snapshot.costUsage?.confidence, .unavailable)
    }
}
