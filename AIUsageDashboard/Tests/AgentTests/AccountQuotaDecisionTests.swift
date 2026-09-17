import XCTest
@testable import AIUsageDashboardCore

final class AccountQuotaDecisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func window(
        _ percent: Double,
        confidence: MetricConfidence = .providerReported,
        observedAt: Date? = nil,
        type: QuotaWindowType = .weekly,
        resetAt: Date? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .claudeCode,
            type: type,
            used: percent,
            limit: 100,
            remaining: 100 - percent,
            resetAt: resetAt ?? now.addingTimeInterval(86_400),
            confidence: confidence,
            source: "fixture",
            observedAt: observedAt
        )
    }

    private func account(
        _ legacyID: String,
        accountID: String,
        status: AccountQuotaStatus = .eligible,
        windows: [QuotaWindow]
    ) -> ProviderAccountUsage {
        ProviderAccountUsage(
            id: legacyID,
            accountID: accountID,
            label: legacyID,
            quotaWindows: windows,
            todayUsage: .unavailable,
            quotaStatus: status
        )
    }

    func testA1_headlineAndRecommendationUseTheSameTrustedAccountDecision() {
        let estimatedA = account(
            "/a",
            accountID: "claude_code:a",
            windows: [window(10, confidence: .estimated, observedAt: now)]
        )
        let officialB = account(
            "/b",
            accountID: "claude_code:b",
            windows: [window(50, observedAt: now)]
        )

        let headline = AccountQuotaDecision.headline(
            among: [estimatedA, officialB],
            providerID: .claudeCode,
            now: now
        )

        XCTAssertEqual(headline?.account.accountID, "claude_code:b")
        XCTAssertEqual(headline?.usedPercent, 50)
    }

    func testA2_staleOfficialAccountNeverBeatsFreshTrustedAccount() {
        let staleA = account(
            "/a",
            accountID: "claude_code:a",
            windows: [window(10, observedAt: now.addingTimeInterval(-1_801))]
        )
        let freshB = account(
            "/b",
            accountID: "claude_code:b",
            windows: [window(50, observedAt: now)]
        )

        let headline = AccountQuotaDecision.headline(
            among: [staleA, freshB],
            providerID: .claudeCode,
            now: now
        )

        XCTAssertEqual(headline?.account.accountID, "claude_code:b")
    }

    func testA2_untrustedPeakMakesTheWholeAccountIneligible() {
        let mixedA = account(
            "/a",
            accountID: "claude_code:a",
            windows: [
                window(1, observedAt: now, type: .session),
                window(10, confidence: .estimated, observedAt: now, type: .weekly)
            ]
        )
        let freshB = account(
            "/b",
            accountID: "claude_code:b",
            windows: [window(50, observedAt: now)]
        )

        let rejected = AccountQuotaDecision.evaluate(
            mixedA,
            providerID: .claudeCode,
            now: now
        )
        let headline = AccountQuotaDecision.headline(
            among: [mixedA, freshB],
            providerID: .claudeCode,
            now: now
        )

        XCTAssertNil(rejected.headroomPercent)
        XCTAssertEqual(rejected.status, .unknown)
        XCTAssertEqual(rejected.usedPercent, 10)
        XCTAssertEqual(rejected.bindingWindowIndex, 1)
        XCTAssertEqual(headline?.account.accountID, "claude_code:b")
    }

    func testA2_tiesUseAccountIDThenStableWindowOrder() {
        let accountB = account(
            "/b",
            accountID: "claude_code:b",
            windows: [
                window(50, observedAt: now, type: .session),
                window(50, observedAt: now, type: .weekly)
            ]
        )
        let accountA = account(
            "/a",
            accountID: "claude_code:a",
            windows: [window(50, observedAt: now)]
        )

        let bDecision = AccountQuotaDecision.evaluate(
            accountB,
            providerID: .claudeCode,
            now: now
        )
        let headline = AccountQuotaDecision.headline(
            among: [accountB, accountA],
            providerID: .claudeCode,
            now: now
        )

        XCTAssertEqual(bDecision.bindingWindowIndex, 0)
        XCTAssertEqual(headline?.account.accountID, "claude_code:a")
    }

    func testA2_futureTimestampBeyondClockSkewIsNotHeadroom() {
        let future = account(
            "/future",
            accountID: "claude_code:future",
            windows: [window(
                10,
                observedAt: now.addingTimeInterval(RouteTargetPolicy.maxClockSkew + 1)
            )]
        )

        let decision = AccountQuotaDecision.evaluate(
            future,
            providerID: .claudeCode,
            now: now
        )

        XCTAssertEqual(decision.status, .unknown)
        XCTAssertNil(decision.headroomPercent)
    }

    func testA2_emptyAndAllUnknownAccountsProduceNoHeadline() {
        let empty = account(
            "/empty",
            accountID: "claude_code:empty",
            windows: []
        )
        let unknown = account(
            "/unknown",
            accountID: "claude_code:unknown",
            status: .unknown,
            windows: [window(5, observedAt: now)]
        )

        XCTAssertNil(AccountQuotaDecision.headline(
            among: [empty, unknown],
            providerID: .claudeCode,
            now: now
        ))
    }

    func testA2_expiredResetCannotProduceHeadroom() {
        let expiredResetWindow = QuotaWindow(
            providerID: .claudeCode,
            type: .weekly,
            used: 10,
            limit: 100,
            resetAt: now.addingTimeInterval(-1),
            confidence: .providerReported,
            source: "fixture",
            observedAt: now
        )
        let expired = account(
            "/expired-reset",
            accountID: "claude_code:expired-reset",
            windows: [expiredResetWindow]
        )

        XCTAssertFalse(AccountQuotaDecision.evaluate(
            expired,
            providerID: .claudeCode,
            now: now
        ).isEligible)
    }

    func testA5_nonEligibleAccountNeverGetsHeadroom() {
        let expired = account(
            "/expired",
            accountID: "claude_code:expired",
            status: .expiredCredentials,
            windows: []
        )

        let decision = AccountQuotaDecision.evaluate(
            expired,
            providerID: .claudeCode,
            now: now
        )

        XCTAssertEqual(decision.status, .expiredCredentials)
        XCTAssertNil(decision.usedPercent)
        XCTAssertNil(decision.headroomPercent)
        XCTAssertNil(decision.validUntil)
    }

    func testR09_04_staleNonPeakWindowMakesAccountIneligible() {
        let mixedA = account(
            "/a",
            accountID: "claude_code:a",
            windows: [
                window(1, observedAt: now.addingTimeInterval(-1_801), type: .session),
                window(20, observedAt: now, type: .weekly)
            ]
        )
        let freshB = account(
            "/b",
            accountID: "claude_code:b",
            windows: [window(50, observedAt: now)]
        )

        let headline = AccountQuotaDecision.headline(
            among: [mixedA, freshB],
            providerID: .claudeCode,
            now: now
        )

        XCTAssertEqual(headline?.account.accountID, "claude_code:b")
    }

    func testR09_04_validUntilIncludesEveryApplicableObservation() throws {
        let sessionObservedAt = now.addingTimeInterval(-1_799)
        let mixed = account(
            "/a",
            accountID: "claude_code:a",
            windows: [
                window(1, observedAt: sessionObservedAt, type: .session),
                window(20, observedAt: now, type: .weekly)
            ]
        )

        let decision = AccountQuotaDecision.evaluate(mixed, providerID: .claudeCode, now: now)

        XCTAssertLessThanOrEqual(
            try XCTUnwrap(decision.validUntil),
            sessionObservedAt.addingTimeInterval(RouteTargetPolicy.agent.maxRoutableAge)
        )
    }

    func testR09_04_validUntilIncludesEveryApplicableReset() throws {
        let resetAt = now.addingTimeInterval(1)
        let mixed = account(
            "/a",
            accountID: "claude_code:a",
            windows: [
                window(1, observedAt: now, type: .session, resetAt: resetAt),
                window(20, observedAt: now, type: .weekly)
            ]
        )

        let decision = AccountQuotaDecision.evaluate(mixed, providerID: .claudeCode, now: now)

        XCTAssertLessThanOrEqual(try XCTUnwrap(decision.validUntil), resetAt)
    }

    func testR09_04_mixedConfidenceTiedPeaksAreIneligibleRegardlessOfOrder() {
        let official = window(20, observedAt: now, type: .session)
        let estimated = window(20, confidence: .estimated, observedAt: now, type: .weekly)

        for windows in [[official, estimated], [estimated, official]] {
            let decision = AccountQuotaDecision.evaluate(
                account("/a", accountID: "claude_code:a", windows: windows),
                providerID: .claudeCode,
                now: now
            )
            XCTAssertFalse(decision.isEligible)
            XCTAssertEqual(decision.status, .unknown)
        }
    }
}
