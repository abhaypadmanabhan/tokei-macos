import XCTest
@testable import AIUsageDashboardCore

final class AgentSnapshotWriterTests: XCTestCase {
    private var tempDirectory: URL!

    // Whole-second dates: the ISO8601 encoding drops sub-second precision, so these
    // round-trip exactly.
    private let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func window(
        _ type: QuotaWindowType,
        used: Double?,
        limit: Double? = 100,
        remaining: Double? = nil,
        confidence: MetricConfidence = .exact,
        source: String = "test_source",
        resetAt: Date? = nil,
        observedAt: Date? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .claudeCode,
            type: type,
            used: used,
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
            confidence: confidence,
            source: source,
            observedAt: observedAt
        )
    }

    private func snapshot(
        _ providerID: ProviderID,
        displayName: String,
        windows: [QuotaWindow],
        todayTokens: Int? = nil,
        lastSyncedAt: Date? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: displayName,
            authStatus: .authenticated,
            quotaWindows: windows,
            todayUsage: TokenUsage(inputTokens: todayTokens, confidence: .localParsed),
            weekUsage: .unavailable,
            lastSyncedAt: lastSyncedAt
        )
    }

    // MARK: - Schema encoding

    func testBuildSnapshotMapsProviderFields() {
        let snap = snapshot(
            .claudeCode,
            displayName: "Claude Code",
            windows: [window(.fiveHour, used: 42, confidence: .providerReported, source: "oauth_usage_api")],
            todayTokens: 1000,
            lastSyncedAt: generatedAt
        )

        let result = AgentSnapshotWriter.buildSnapshot(from: [snap], generatedAt: generatedAt)

        XCTAssertEqual(result.schemaVersion, AgentSnapshot.currentSchemaVersion)
        XCTAssertEqual(result.generatedAt, generatedAt)
        XCTAssertEqual(result.providers.count, 1)
        let provider = result.providers[0]
        XCTAssertEqual(provider.id, "claude_code")
        XCTAssertEqual(provider.displayName, "Claude Code")
        XCTAssertEqual(provider.tokensToday, 1000)
        XCTAssertEqual(provider.lastUpdated, generatedAt)
        XCTAssertEqual(provider.windows.count, 1)
        XCTAssertEqual(provider.windows[0].type, "fiveHour")
        XCTAssertEqual(provider.windows[0].usedPercent, 42)
        XCTAssertEqual(provider.windows[0].source, "oauth_usage_api")
        // providerReported collapses to the public "official" label.
        XCTAssertEqual(provider.windows[0].confidence, "official")
    }

    func testConfidenceCollapsesToPublicLabels() {
        func label(_ confidence: MetricConfidence) -> String? {
            let win = window(.weekly, used: 10, confidence: confidence)
            return AgentSnapshotWriter.buildSnapshot(
                from: [snapshot(.codex, displayName: "Codex", windows: [win])],
                generatedAt: generatedAt
            ).providers[0].windows.first?.confidence
        }
        XCTAssertEqual(label(.exact), "official")
        XCTAssertEqual(label(.providerReported), "official")
        XCTAssertEqual(label(.localParsed), "local_estimate")
        XCTAssertEqual(label(.estimated), "local_estimate")
        XCTAssertEqual(label(.unavailable), "unavailable")
    }

    func testWindowsWithoutComputablePercentAreOmitted() {
        // No limit, and no used/remaining → not a computable percentage → dropped.
        let snap = snapshot(
            .codex,
            displayName: "Codex",
            windows: [
                window(.weekly, used: nil, limit: nil), // dropped
                window(.daily, used: nil, remaining: 30), // used = 100-30 = 70 → kept
                window(.monthly, used: 55) // kept
            ]
        )
        let provider = AgentSnapshotWriter.buildSnapshot(from: [snap], generatedAt: generatedAt).providers[0]
        XCTAssertEqual(provider.windows.count, 2)
        XCTAssertEqual(provider.windows.map(\.type).sorted(), ["daily", "monthly"])
        XCTAssertEqual(provider.windows.first(where: { $0.type == "daily" })?.usedPercent, 70)
    }

    /// The public schema must expose *when* a reading was taken, so an agent can judge
    /// freshness itself instead of parsing `"(stale)"` out of a diagnostic string.
    /// Additive, so `schemaVersion` stays 1.
    func testObservedAtIsExposedOnPublicWindows() {
        let observed = generatedAt.addingTimeInterval(-3600)
        let snap = snapshot(
            .claudeCode,
            displayName: "Claude Code",
            windows: [window(.weekly, used: 0, confidence: .estimated, observedAt: observed)]
        )
        let built = AgentSnapshotWriter.buildSnapshot(from: [snap], generatedAt: generatedAt)
        XCTAssertEqual(built.providers[0].windows[0].observedAt, observed)
        XCTAssertEqual(built.schemaVersion, 1)
    }

    /// Multi-account providers must expose the breakdown, not just an aggregate. An
    /// orchestrator deciding where to fan out needs to know *which* Claude account has
    /// headroom — that's the whole point of tracking more than one.
    func testPerAccountUsageIsExposedInThePublicSchema() throws {
        let snap = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            quotaWindows: [window(.weekly, used: 10)],
            todayUsage: TokenUsage(outputTokens: 300, confidence: .localParsed),
            weekUsage: TokenUsage(outputTokens: 300, confidence: .localParsed),
            accounts: [
                ProviderAccountUsage(
                    id: "/Users/x/.claude", label: "default",
                    quotaWindows: [window(.weekly, used: 90)],
                    todayUsage: TokenUsage(outputTokens: 100, confidence: .localParsed)
                ),
                ProviderAccountUsage(
                    id: "/Users/x/.claude-account-1", label: "account-1",
                    quotaWindows: [window(.weekly, used: 10)],
                    todayUsage: TokenUsage(outputTokens: 200, confidence: .localParsed)
                )
            ]
        )

        let provider = AgentSnapshotWriter.buildSnapshot(from: [snap], generatedAt: generatedAt).providers[0]

        XCTAssertEqual(provider.accounts?.map(\.label), ["default", "account-1"])
        XCTAssertEqual(provider.accounts?.first?.windows.first?.usedPercent, 90)
        XCTAssertEqual(provider.accounts?.last?.tokensToday, 200)
    }

    /// Single-account providers must not grow an empty `accounts` array — the field is
    /// absent, not empty, so existing readers see no change at all.
    func testSingleAccountProvidersOmitTheAccountsField() {
        let snap = snapshot(.codex, displayName: "Codex", windows: [window(.weekly, used: 55)])
        let provider = AgentSnapshotWriter.buildSnapshot(from: [snap], generatedAt: generatedAt).providers[0]
        XCTAssertNil(provider.accounts)
    }

    func testUsedPercentClampsToHundred() {
        let snap = snapshot(.codex, displayName: "Codex", windows: [window(.weekly, used: 150, limit: 100)])
        let percent = AgentSnapshotWriter.buildSnapshot(from: [snap], generatedAt: generatedAt)
            .providers[0].windows[0].usedPercent
        XCTAssertEqual(percent, 100)
    }

    func testSchemaRoundTripsThroughJSON() throws {
        let snaps = [
            snapshot(.claudeCode, displayName: "Claude Code",
                     windows: [window(.fiveHour, used: 42, resetAt: generatedAt)],
                     todayTokens: 1000, lastSyncedAt: generatedAt),
            snapshot(.antigravity, displayName: "Antigravity",
                     windows: [window(.weekly, used: 92)], todayTokens: 250, lastSyncedAt: generatedAt)
        ]
        let built = AgentSnapshotWriter.buildSnapshot(from: snaps, generatedAt: generatedAt)

        let data = try AgentSnapshot.makeEncoder().encode(built)
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)

        XCTAssertEqual(decoded, built)
    }

    func testEncodedSnapshotContainsNoSecretShapedFields() throws {
        let snaps = [snapshot(.claudeCode, displayName: "Claude Code",
                              windows: [window(.fiveHour, used: 42, source: "oauth_usage_api")], todayTokens: 1000)]
        let built = AgentSnapshotWriter.buildSnapshot(from: snaps, generatedAt: generatedAt)
        let data = try AgentSnapshot.makeEncoder().encode(built)
        let json = try XCTUnwrap(String(bytes: data, encoding: .utf8)).lowercased()

        let forbiddenTerms = [
            "access_token", "refresh_token", "authorization", "\"cookie\"",
            "bearer", "password", "\"secret\"", "api_key", "apikey"
        ]
        for forbidden in forbiddenTerms {
            XCTAssertFalse(json.contains(forbidden), "snapshot JSON must not contain \(forbidden)")
        }
    }

    // MARK: - Atomic write

    func testWriteProducesDecodableFile() async throws {
        let writer = AgentSnapshotWriter(directory: tempDirectory)
        let succeeded = await writer.write(
            from: [snapshot(.codex, displayName: "Codex", windows: [window(.weekly, used: 31)], todayTokens: 500)],
            generatedAt: generatedAt
        )
        XCTAssertTrue(succeeded)

        let location = await writer.location
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.path))
        let decoded = try AgentSnapshot.makeDecoder().decode(
            AgentSnapshot.self, from: Data(contentsOf: location)
        )
        XCTAssertEqual(decoded.providers.first?.id, "codex")
        XCTAssertEqual(decoded.providers.first?.windows.first?.usedPercent, 31)
        // Reader-only fields are omitted on disk.
        XCTAssertNil(decoded.stale)
        XCTAssertNil(decoded.ageSeconds)
    }

    func testWriteOverwritesPreviousSnapshot() async throws {
        let writer = AgentSnapshotWriter(directory: tempDirectory)
        await writer.write(
            from: [snapshot(.codex, displayName: "Codex", windows: [window(.weekly, used: 10)])],
            generatedAt: generatedAt
        )
        await writer.write(
            from: [snapshot(.codex, displayName: "Codex", windows: [window(.weekly, used: 80)])],
            generatedAt: generatedAt
        )

        let location = await writer.location
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: Data(contentsOf: location))
        XCTAssertEqual(decoded.providers.first?.windows.first?.usedPercent, 80)
    }
}
