import XCTest
@testable import AIUsageDashboardCore

/// The rules `CursorUsageClient` and `AntigravityQuotaClient` both delegate to.
/// Tested directly so a client adopting them can't quietly re-derive a different rule.
final class UsageClientPolicyTests: XCTestCase {
    private let defaultCooldown: TimeInterval = 300

    // MARK: - Retry-After ceiling

    func testRetryAfterLongerThanCeilingGivesUpOnTheFirstAttempt() {
        let action = UsageClientPolicy.rateLimitAction(
            retryAfter: 120,
            attempt: 1,
            maxAttempts: 3,
            defaultCooldownInterval: defaultCooldown
        )
        XCTAssertEqual(action, .giveUp(retryAfter: 120))
    }

    func testRetryAfterExactlyAtCeilingIsStillSlept() {
        // Boundary: the ceiling is what we're willing to wait, so `== ceiling` sleeps.
        let action = UsageClientPolicy.rateLimitAction(
            retryAfter: UsageClientPolicy.maxRetrySleepInterval,
            attempt: 1,
            maxAttempts: 3,
            defaultCooldownInterval: defaultCooldown
        )
        XCTAssertEqual(action, .sleepThenRetry(UsageClientPolicy.maxRetrySleepInterval))
    }

    func testShortRetryAfterIsHonouredVerbatim() {
        let action = UsageClientPolicy.rateLimitAction(
            retryAfter: 5,
            attempt: 1,
            maxAttempts: 3,
            defaultCooldownInterval: defaultCooldown
        )
        XCTAssertEqual(action, .sleepThenRetry(5))
    }

    func testMissingRetryAfterFallsBackToTheDefaultCooldownClampedToTheCeiling() {
        let action = UsageClientPolicy.rateLimitAction(
            retryAfter: nil,
            attempt: 1,
            maxAttempts: 3,
            defaultCooldownInterval: defaultCooldown
        )
        XCTAssertEqual(action, .sleepThenRetry(UsageClientPolicy.maxRetrySleepInterval))
    }

    func testLastAttemptGivesUpRatherThanSleepingPointlessly() {
        let action = UsageClientPolicy.rateLimitAction(
            retryAfter: 5,
            attempt: 3,
            maxAttempts: 3,
            defaultCooldownInterval: defaultCooldown
        )
        XCTAssertEqual(action, .giveUp(retryAfter: 5))
    }

    func testGiveUpCarriesNilWhenTheServerSentNoRetryAfter() {
        let action = UsageClientPolicy.rateLimitAction(
            retryAfter: nil,
            attempt: 3,
            maxAttempts: 3,
            defaultCooldownInterval: defaultCooldown
        )
        XCTAssertEqual(action, .giveUp(retryAfter: nil))
    }

    // MARK: - observedAt stamping

    func testObservedStampsEveryWindow() {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stamped = UsageClientPolicy.observed([window(used: 10), window(used: 20)], at: observedAt)

        XCTAssertEqual(stamped.map(\.observedAt), [observedAt, observedAt])
        XCTAssertEqual(stamped.map(\.used), [10, 20])
        XCTAssertEqual(stamped.map(\.confidence), [.providerReported, .providerReported])
    }

    func testReplayedFromCacheDowngradesConfidenceAndStampsObservationTimeWithoutTouchingSource() {
        let cachedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let replayed = UsageClientPolicy.replayedFromCache([window(used: 10)], observedAt: cachedAt)

        let first = try? XCTUnwrap(replayed.first)
        XCTAssertEqual(first?.confidence, .estimated)
        XCTAssertEqual(first?.observedAt, cachedAt)
        // Staleness is a number, not a string suffix.
        XCTAssertEqual(first?.source, "test-source")
        XCTAssertFalse(first?.source.contains("stale") ?? true)
        XCTAssertEqual(first?.used, 10)
        XCTAssertEqual(first?.remaining, 90)
        XCTAssertEqual(first?.bucketKey, "bucket")
    }

    private func window(used: Double) -> QuotaWindow {
        QuotaWindow(
            providerID: .antigravity,
            type: .weekly,
            used: used,
            limit: 100,
            remaining: 100 - used,
            resetAt: Date(timeIntervalSince1970: 1_800_000_000),
            confidence: .providerReported,
            source: "test-source",
            label: "label",
            bucketKey: "bucket"
        )
    }
}
