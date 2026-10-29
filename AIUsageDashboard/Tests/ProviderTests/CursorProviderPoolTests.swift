import XCTest
@testable import AIUsageDashboardCore

extension CursorProviderTests {
    func testOnlyOverallUsagePublishesOneWindowWithExistingPlanLabel() async throws {
        let stateDB = tempDirectory.appendingPathComponent("state.vscdb")
        try createStateDatabase(at: stateDB, rows: offlineRows(tabAccepted: 0, composerAccepted: 0))
        userDefaults.set(true, forKey: "cursorNetworkUsageEnabled")
        let summary = """
        {"membershipType":"pro","billingCycleEnd":"2026-07-31T00:00:00.000Z",
         "individualUsage":{"plan":{"totalPercentUsed":42.5}}}
        """
        let client = MockCursorUsageClient(
            csv: .success(CursorFixtures.usageEventsCSV), summary: .success(Data(summary.utf8))
        )
        let snapshot = try await makeProvider(stateDB: stateDB, client: client).fetchSnapshot()

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let quota = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(quota.used, 42.5)
        XCTAssertEqual(quota.remaining, 57.5)
        XCTAssertEqual(quota.label, "Pro (active)")
        XCTAssertNil(quota.bucketKey)
        XCTAssertEqual(quota.observedAt, referenceNow)
    }
}
