import XCTest
@testable import AIUsageDashboardCore

/// Cursor 3.x encrypts its sign-in at rest, and a Super plan spends the SuperGrok pool.
extension CursorProviderTests {
    /// Shape of a Cursor 3.31 `cursorAuth/accessToken` (fake body).
    static let encryptedToken = "cursor-safe-storage:v1:" + String(repeating: "QUJD", count: 40)

    func testEncryptedSignInSaysWhyAndSendsNoRequest() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        var rows = offlineRows(tabAccepted: 0, composerAccepted: 0)
        rows["cursorAuth/accessToken"] = Self.encryptedToken
        rows["cursorAuth/stripeMembershipType"] = "super"
        try createStateDatabase(at: stateDB, rows: rows)
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let client = CountingCursorClient()
        let snapshot = try await makeProvider(stateDB: stateDB, client: client).fetchSnapshot()

        XCTAssertEqual(client.calls.value, 0)
        XCTAssertEqual(snapshot.authStatus, .authenticated)
        XCTAssertTrue(snapshot.quotaWindows.isEmpty)
        let messages = snapshot.warnings.map(\.message)
        XCTAssertTrue(messages.contains("Plan: Super (active)"))
        XCTAssertTrue(messages.contains {
            $0.contains("encrypted in the macOS keychain") && $0.contains("SuperGrok pool")
        })
        XCTAssertFalse(messages.contains { $0.contains("no Cursor session could be read") })
    }

    func testEncryptedSignInOnOtherPlansDoesNotMentionThePool() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        var rows = offlineRows(tabAccepted: 0, composerAccepted: 0)
        rows["cursorAuth/accessToken"] = Self.encryptedToken
        try createStateDatabase(at: stateDB, rows: rows)
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")

        let snapshot = try await makeProvider(stateDB: stateDB, client: CountingCursorClient()).fetchSnapshot()
        let warning = try XCTUnwrap(snapshot.warnings.first { $0.message.contains("encrypted") })
        XCTAssertFalse(warning.message.contains("SuperGrok"))
    }

    func testSuperPlanSummaryIsTaggedAsTheSharedSuperGrokPool() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        var rows = offlineRows(tabAccepted: 0, composerAccepted: 0)
        rows["cursorAuth/stripeMembershipType"] = "super"
        try createStateDatabase(at: stateDB, rows: rows)
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")
        // Super with the auto/api split present still publishes one pool, not two pools.
        let summary = """
        {"billingCycleEnd":"2026-07-31T00:00:00.000Z",
         "individualUsage":{"plan":{"totalPercentUsed":7,"autoPercentUsed":5,"apiPercentUsed":9}}}
        """
        let client = MockCursorUsageClient(
            csv: .success(CursorFixtures.usageEventsCSV), summary: .success(Data(summary.utf8))
        )
        let snapshot = try await makeProvider(stateDB: stateDB, client: client).fetchSnapshot()

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let pool = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(pool.used, 7)
        XCTAssertEqual(pool.bucketKey, SharedQuotaPool.superGrokBucketKey)
        XCTAssertEqual(pool.label, SharedQuotaPool.superGrokLabel)
    }

    func testEncryptedTokenIsNeverTreatedAsAJWT() {
        XCTAssertTrue(CursorSession.isEncryptedAtRest(Self.encryptedToken))
        XCTAssertFalse(CursorSession.isEncryptedAtRest(CursorFixtures.jwtPlaceholder))
        XCTAssertNil(CursorSession.cookie(jwt: Self.encryptedToken))
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private struct CountingCursorClient: CursorUsageClient {
    let calls = CallCounter()
    func fetchUsageEventsCSV(cookie: String) async throws -> String {
        calls.increment()
        throw CursorUsageError.unexpectedResponse
    }
    func fetchUsageSummary(cookie: String) async throws -> Data {
        calls.increment()
        throw CursorUsageError.unexpectedResponse
    }
}
