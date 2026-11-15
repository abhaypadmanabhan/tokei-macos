import XCTest
@testable import AIUsageDashboardCore

final class ExpiringHeadroomTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFlagsPlanWindowResettingSoonWithRoomLeft() {
        let found = ExpiringHeadroomFinder.find(in: [
            snapshot(.codex, windows: [window(.codex, .fiveHour, used: 38, resetIn: 41 * 60)])
        ], now: now)

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.providerID, .codex)
        XCTAssertEqual(found.first?.unusedPercent ?? 0, 62, accuracy: 0.001)
        XCTAssertEqual(found.first?.secondsToReset(from: now), 41 * 60)
    }

    func testIgnoresWindowsOutsideTheirHorizonOrMostlyUsed() {
        let found = ExpiringHeadroomFinder.find(in: [
            snapshot(.codex, windows: [
                window(.codex, .fiveHour, used: 38, resetIn: 2 * 3_600, bucket: "far"),
                window(.codex, .weekly, used: 90, resetIn: 3_600, bucket: "full"),
                window(.codex, .weekly, used: 10, resetIn: 30 * 3_600, bucket: "weekly-far")
            ])
        ], now: now)

        XCTAssertTrue(found.isEmpty)
    }

    func testNeverFlagsPaidCreditsPerModelOrUntrustedReadings() {
        let found = ExpiringHeadroomFinder.find(in: [
            snapshot(.claudeCode, windows: [
                window(.claudeCode, .credits, used: 1, resetIn: 600, bucket: "claude_extra_usage"),
                window(.claudeCode, .perModel, used: 0, resetIn: 600, bucket: "opus"),
                window(.claudeCode, .fiveHour, used: 0, resetIn: 600, bucket: "estimated", confidence: .estimated),
                window(.claudeCode, .fiveHour, used: 0, resetIn: 600, bucket: "old", observedAgo: 31 * 60)
            ])
        ], now: now)

        XCTAssertTrue(found.isEmpty, "credits are paid spend; estimates and old readings are not headroom")
    }

    func testIndividualCapNeverExpiresRegardlessOfRebuiltWindowType() {
        for type in QuotaWindowType.allCases {
            let cap = window(.codex, type, used: 10, resetIn: 600, bucket: "spend_control_individual_limit")
            for accounts in [nil, [account("fixture", windows: [cap], status: .eligible)]] as [[ProviderAccountUsage]?] {
                let found = ExpiringHeadroomFinder.find(in: [snapshot(.codex, windows: [cap], accounts: accounts)], now: now)
                XCTAssertTrue(found.isEmpty, "a spending cap is never expiring capacity: \(type)")
            }
        }
    }

    @MainActor
    func testIndividualCapNeverReachesBurnNudgesBoardCLIOrMCP() throws {
        let instant = Date()
        let cap = QuotaWindow(providerID: .codex, type: .monthly, used: 10, limit: 100,
                              resetAt: instant.addingTimeInterval(600), confidence: .providerReported,
                              source: "fixture", bucketKey: "spend_control_individual_limit", observedAt: instant)
        let plan = QuotaWindow(providerID: .claudeCode, type: .fiveHour, used: 40, limit: 100,
                               resetAt: instant.addingTimeInterval(1_800), confidence: .providerReported,
                               source: "fixture", observedAt: instant)
        let input = [snapshot(.codex, windows: [cap]), snapshot(.claudeCode, windows: [plan])]
        let burn = BurnEngine.evaluate(snapshots: input, monthlyPlanUSD: [.codex: 20, .claudeCode: 20],
                                       quotaSamples: [], state: BurnState(), now: instant,
                                       calendar: BurnFixtures().calendar, pricing: BurnFixtures().pricing,
                                       emitMoments: false).snapshot
        XCTAssertEqual(burn.expiring.map(\.providerID), [.claudeCode])
        let board = BurnBoard(snapshot: burn, now: { instant })
        XCTAssertEqual(board.snapshot.expiring.map(\.providerID), [.claudeCode], "the Burn tab renders this exact list")
        let nudges = BurnNudge.candidates(snapshot: burn, delivered: [:], windowKeys: [], now: instant)
        XCTAssertEqual(nudges.compactMap { $0.windowKey?.providerID }, [.claudeCode])

        let exported = AgentSnapshotWriter.buildSnapshot(from: input, generatedAt: instant, burn: burn)
        XCTAssertEqual(exported.burn?.expiring.map(\.provider), ["claude_code"])
        let cli = try ReviewCLIProbe.run(["burn"], snapshot: exported)
        XCTAssertEqual(cli.status, 0)
        XCTAssertTrue(cli.text.contains("claude_code"))
        XCTAssertFalse(cli.text.lowercased().contains("codex"))

        let directory = try CLITestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try CLITestSupport.writeSnapshot(exported, in: directory)
        let helper = try MCPProcessHarness(snapshotURL: url)
        defer { helper.stop() }
        try helper.write(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_burn_opportunities"}}"# + "\n")
        let response = try helper.response(id: 1, timeout: 2)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let text = try toolCallText(result)
        XCTAssertFalse(text.isError)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.text.utf8)) as? [String: Any])
        let rows = try XCTUnwrap(payload["expiring"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["provider"] as? String }, ["claude_code"])
    }

    func testWindowAlreadyResetIsNotExpiring() {
        let found = ExpiringHeadroomFinder.find(in: [
            snapshot(.codex, windows: [window(.codex, .fiveHour, used: 0, resetIn: -60)])
        ], now: now)

        XCTAssertTrue(found.isEmpty)
    }

    func testUsesEligibleAccountRowsInsteadOfTheHeadlineCopy() {
        let headline = window(.claudeCode, .fiveHour, used: 20, resetIn: 1_800, bucket: "five")
        let accounts = [
            account("a", windows: [headline], status: .eligible),
            account("b", windows: [window(.claudeCode, .fiveHour, used: 50, resetIn: 600, bucket: "five")], status: .eligible),
            account("c", windows: [window(.claudeCode, .fiveHour, used: 0, resetIn: 600, bucket: "five")], status: .cooldown)
        ]
        let found = ExpiringHeadroomFinder.find(in: [
            snapshot(.claudeCode, windows: [headline], accounts: accounts)
        ], now: now)

        XCTAssertEqual(found.map(\.accountID), ["id-b", "id-a"], "soonest reset first; cooldown account skipped")
        XCTAssertEqual(found.map(\.accountLabel), ["b", "a"])
    }

    func testSortsSoonestResetFirstAcrossProviders() {
        let found = ExpiringHeadroomFinder.find(in: [
            snapshot(.claudeCode, windows: [window(.claudeCode, .weekly, used: 40, resetIn: 5 * 3_600)]),
            snapshot(.codex, windows: [window(.codex, .fiveHour, used: 10, resetIn: 20 * 60)])
        ], now: now)

        XCTAssertEqual(found.map(\.providerID), [.codex, .claudeCode])
    }

    // MARK: - Fixtures

    private func window(
        _ provider: ProviderID,
        _ type: QuotaWindowType,
        used: Double,
        resetIn: TimeInterval,
        bucket: String? = nil,
        confidence: MetricConfidence = .providerReported,
        observedAgo: TimeInterval = 60
    ) -> QuotaWindow {
        QuotaWindow(providerID: provider, type: type, used: used, limit: 100, remaining: 100 - used,
                    resetAt: now.addingTimeInterval(resetIn), confidence: confidence, source: "test",
                    bucketKey: bucket, observedAt: now.addingTimeInterval(-observedAgo))
    }

    private func account(_ label: String, windows: [QuotaWindow], status: AccountQuotaStatus) -> ProviderAccountUsage {
        ProviderAccountUsage(id: "/tmp/\(label)", accountID: "id-\(label)", label: label, quotaWindows: windows,
                             todayUsage: .unavailable, quotaStatus: status)
    }

    private func snapshot(
        _ provider: ProviderID,
        windows: [QuotaWindow],
        accounts: [ProviderAccountUsage]? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(providerID: provider, displayName: provider.rawValue, authStatus: .authenticated,
                         quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable,
                         accounts: accounts)
    }
}
