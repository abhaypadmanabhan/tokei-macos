import XCTest
@testable import AIUsageDashboardCore

final class AgentSnapshotAccountSchemaTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
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

    private func freshWindow(_ providerID: ProviderID, used: Double) -> QuotaWindow {
        QuotaWindow(
            providerID: providerID,
            type: .weekly,
            used: used,
            limit: 100,
            resetAt: generatedAt.addingTimeInterval(3_600),
            confidence: .providerReported,
            source: "fixture",
            observedAt: generatedAt
        )
    }

    func testA4_expiryHelperDropsRouteAndTargetOneSecondAfterValidUntil() throws {
        let validUntil = generatedAt.addingTimeInterval(600)
        let recommendation = AgentRecommendation(
            routeTo: "codex",
            avoid: [],
            reason: "route to Codex",
            target: AgentRecommendationTarget(
                provider: "codex",
                accountID: "codex:one",
                selector: AccountSelector(env: [
                    "CODEX_HOME": FileManager.default.temporaryDirectory.path
                ])
            ),
            avoidAccounts: [],
            validUntil: validUntil
        )
        let snapshot = AgentSnapshot(
            generatedAt: generatedAt,
            providers: [],
            aggregateUtilizationPercent: nil,
            recommendation: recommendation
        )

        XCTAssertEqual(snapshot.withRecommendationValidity(asOf: validUntil).recommendation?.routeTo, "codex")
        let expired = snapshot.withRecommendationValidity(asOf: validUntil.addingTimeInterval(1))
        XCTAssertNil(expired.recommendation?.routeTo)
        XCTAssertNil(expired.recommendation?.target)
        XCTAssertTrue(expired.recommendation?.reason.contains("expired") == true)
    }

    func testA4_unboundedLegacyRecommendationCannotCarryExecutableTarget() {
        let snapshot = AgentSnapshot(
            generatedAt: generatedAt,
            providers: [],
            aggregateUtilizationPercent: nil,
            recommendation: AgentRecommendation(
                routeTo: "codex",
                avoid: [],
                reason: "legacy advice",
                target: AgentRecommendationTarget(
                    provider: "codex",
                    accountID: "codex:one",
                    selector: AccountSelector(env: ["CODEX_HOME": "/tmp/codex"])
                )
            )
        )

        let bounded = snapshot.withRecommendationValidity(asOf: generatedAt)

        XCTAssertEqual(bounded.recommendation?.routeTo, "codex")
        XCTAssertNil(bounded.recommendation?.target)
    }

    func testA5_old080SnapshotStillDecodesWithAdditionsAbsent() throws {
        let data = Data(AgentSnapshotFixtures.oldOptionalFieldsAbsent.utf8)
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.providers.first?.headlineAccountID)
        XCTAssertNil(decoded.providers.first?.accounts)
        XCTAssertNil(decoded.recommendation)
    }

    func testA5_exactTwoAccountJSONFixtureDecodesAndReencodesFieldForField() throws {
        let fixtureData = Data(AgentSnapshotFixtures.wp5SchemaAfter.utf8)
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: fixtureData)
        let encoded = try AgentSnapshot.makeEncoder().encode(decoded)
        let expected = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? NSDictionary
        )
        let actual = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? NSDictionary
        )

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(actual, expected)
    }

    func testA5_newSnapshotDecodesInLegacy080ShapeAndDropsAdditions() throws {
        let fixtureData = Data(AgentSnapshotFixtures.wp5SchemaAfter.utf8)
        let legacy = try AgentSnapshot.makeDecoder().decode(Legacy080Snapshot.self, from: fixtureData)
        let encoded = try AgentSnapshot.makeEncoder().encode(legacy)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let providers = try XCTUnwrap(object["providers"] as? [[String: Any]])
        let claude = try XCTUnwrap(providers.first)
        let accounts = try XCTUnwrap(claude["accounts"] as? [[String: Any]])
        let recommendation = try XCTUnwrap(object["recommendation"] as? [String: Any])

        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertNil(claude["headlineAccountID"])
        XCTAssertNil(accounts[0]["accountID"])
        XCTAssertNil(accounts[0]["selector"])
        XCTAssertNil(accounts[0]["quota"])
        XCTAssertNil(recommendation["target"])
        XCTAssertNil(recommendation["avoidAccounts"])
        XCTAssertNil(recommendation["validUntil"])
    }

    func testA5_selectorRoundTripsLiteralShellShapedPath() throws {
        let path = "/tmp/account with spaces/'quotes'/$(never-run)"
        let selector = AccountSelector(env: ["CODEX_HOME": path])
        let account = AgentAccount(
            id: path,
            label: "literal",
            windows: [],
            tokensToday: nil,
            accountID: "codex:test",
            selector: selector,
            quota: AgentAccountQuota(status: "unknown")
        )
        let provider = AgentProvider(
            id: "codex",
            displayName: "Codex",
            windows: [],
            tokensToday: nil,
            lastUpdated: nil,
            accounts: [account],
            headlineAccountID: nil
        )
        let snapshot = AgentSnapshot(
            generatedAt: generatedAt,
            providers: [provider],
            aggregateUtilizationPercent: nil,
            recommendation: nil
        )

        let encoded = try AgentSnapshot.makeEncoder().encode(snapshot)
        let decoded = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.providers[0].accounts?[0].selector?.env["CODEX_HOME"], path)
        XCTAssertNil(decoded.providers[0].accounts?[0].selector?.env["DYLD_INSERT_LIBRARIES"])
    }

    func testA5_unknownSelectorKeysAreNeverEncoded() throws {
        let selector = AccountSelector(env: [
            "CODEX_HOME": "/tmp/codex",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil"
        ])
        let data = try AgentSnapshot.makeEncoder().encode(selector)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let env = try XCTUnwrap(object["env"] as? [String: String])

        XCTAssertEqual(env, ["CODEX_HOME": "/tmp/codex"])
    }

    func testA5_expiredClaudeAccountExportsBoundedStatusAndNeverRoutesOrAvoids() throws {
        let expiredClaude = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .unknown,
            quotaWindows: [],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            accounts: [ProviderAccountUsage(
                id: "/tmp/.claude",
                accountID: "claude_code:expired",
                label: "default",
                quotaWindows: [],
                todayUsage: .unavailable,
                quotaStatus: .expiredCredentials,
                quotaStatusDetail: "must not be projected"
            )]
        )
        let codex = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            authStatus: .authenticated,
            quotaWindows: [freshWindow(.codex, used: 70)],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
        let cursor = ProviderSnapshot(
            providerID: .cursor,
            displayName: "Cursor",
            authStatus: .authenticated,
            quotaWindows: [freshWindow(.cursor, used: 40)],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )

        let snapshot = AgentSnapshotWriter.buildSnapshot(
            from: [expiredClaude, codex, cursor],
            generatedAt: generatedAt
        )
        let account = try XCTUnwrap(snapshot.providers[0].accounts?.first)

        XCTAssertEqual(account.quota?.status, "expiredCredentials")
        XCTAssertNil(account.quota?.headroomPercent)
        XCTAssertNotEqual(snapshot.recommendation?.routeTo, "claude_code")
        XCTAssertFalse(snapshot.recommendation?.avoid.contains("claude_code") == true)
        XCTAssertFalse(snapshot.recommendation?.avoidAccounts?.contains {
            $0.accountID == "claude_code:expired"
        } == true)
    }

    func testR09_05_relativeSelectorIsNotExportedOrAdvertisedAsATarget() throws {
        let snapshot = executableSnapshot(selector: AccountSelector(env: [
            "CLAUDE_CONFIG_DIR": "relative/profile"
        ]))

        assertSelectorIsNotExecutable(snapshot)
    }

    func testR09_05_nonexistentSelectorIsNotExportedOrAdvertisedAsATarget() throws {
        let missing = tempDirectory.appendingPathComponent("missing", isDirectory: true).path
        let snapshot = executableSnapshot(selector: AccountSelector(env: [
            "CLAUDE_CONFIG_DIR": missing
        ]))

        assertSelectorIsNotExecutable(snapshot)
    }

    func testR09_05_controlCharactersAreNotExecutableSelectors() throws {
        for path in [tempDirectory.path + "\nchild", tempDirectory.path + "\u{7F}child"] {
            let snapshot = executableSnapshot(selector: AccountSelector(env: [
                "CLAUDE_CONFIG_DIR": path
            ]))
            assertSelectorIsNotExecutable(snapshot)
        }
    }

    func testR09_05_crossProviderSelectorMapIsNotExportedOrAdvertised() throws {
        let snapshot = executableSnapshot(selector: AccountSelector(env: [
            "CLAUDE_CONFIG_DIR": tempDirectory.path,
            "CODEX_HOME": tempDirectory.path
        ]))

        assertSelectorIsNotExecutable(snapshot)
    }

    func testR09_05_deletedRootIsRevalidatedAtExportTime() throws {
        let root = tempDirectory.appendingPathComponent("verified-then-deleted", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let selector = try XCTUnwrap(AccountSelector.verified(
            environmentKey: "CLAUDE_CONFIG_DIR",
            root: root
        ))
        try FileManager.default.removeItem(at: root)

        assertSelectorIsNotExecutable(executableSnapshot(selector: selector))
    }

    private func executableSnapshot(selector: AccountSelector) -> AgentSnapshot {
        let claude = ProviderSnapshot(
            providerID: .claudeCode,
            displayName: "Claude Code",
            authStatus: .authenticated,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            accounts: [ProviderAccountUsage(
                id: tempDirectory.path,
                accountID: "claude_code:test",
                selector: selector,
                label: "test",
                quotaWindows: [freshWindow(.claudeCode, used: 20)],
                todayUsage: .unavailable,
                quotaStatus: .eligible
            )]
        )
        let codex = ProviderSnapshot(
            providerID: .codex,
            displayName: "Codex",
            authStatus: .authenticated,
            quotaWindows: [freshWindow(.codex, used: 70)],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
        return AgentSnapshotWriter.buildSnapshot(
            from: [claude, codex],
            generatedAt: generatedAt
        )
    }

    private func assertSelectorIsNotExecutable(
        _ snapshot: AgentSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(
            snapshot.providers.first { $0.id == "claude_code" }?.accounts?.first?.selector,
            file: file,
            line: line
        )
        XCTAssertNil(snapshot.recommendation?.target, file: file, line: line)
    }
}

private struct Legacy080Snapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let providers: [Legacy080Provider]
    let aggregateUtilizationPercent: Double?
    let recommendation: Legacy080Recommendation?
    let stale: Bool?
    let ageSeconds: Int?
}

private struct Legacy080Provider: Codable {
    let id: String
    let displayName: String
    let windows: [Legacy080Window]
    let tokensToday: Int?
    let lastUpdated: Date?
    let accounts: [Legacy080Account]?
}

private struct Legacy080Account: Codable {
    let id: String
    let label: String
    let windows: [Legacy080Window]
    let tokensToday: Int?
}

private struct Legacy080Window: Codable {
    let type: String
    let usedPercent: Double
    let resetsAt: Date?
    let confidence: String
    let source: String
    let observedAt: Date?
}

private struct Legacy080Recommendation: Codable {
    let routeTo: String?
    let avoid: [String]
    let reason: String
}
