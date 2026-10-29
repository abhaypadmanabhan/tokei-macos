import UserNotifications
import XCTest
@testable import AIUsageDashboardCore

final class NotificationReviewTests: XCTestCase {
    private let suite = FileManager.default.temporaryDirectory
        .appendingPathComponent("ai.AIUsageDashboard.NotificationEngineTests.review").path
    private var defaults: UserDefaults!
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "predictiveQuotaWarningsEnabled")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
        defaults = nil
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }

    private func snapshot() -> ProviderSnapshot {
        let window = QuotaWindow(providerID: .claudeCode, type: .weekly, used: 85, limit: 100,
                                 resetAt: instant.addingTimeInterval(3600), confidence: .providerReported,
                                 source: "fixture", bucketKey: "weekly_all")
        return ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            quotaWindows: [window], todayUsage: .unavailable, weekUsage: .unavailable,
            accounts: [ProviderAccountUsage(id: "profile", accountID: "account-a", label: "A",
                                           quotaWindows: [window], todayUsage: .unavailable)],
            headlineAccountID: "profile"
        )
    }

    func testLegacyFutureThresholdMigratesWithoutAnotherNotification() async throws {
        let legacy = FiredNotificationKey(providerID: .claudeCode, windowType: .weekly, threshold: 80,
                                          resetAt: instant.addingTimeInterval(3600))
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "notificationThresholdFiredKeys")
        let center = ReviewNotificationCenter()
        let engine = NotificationEngine(notificationCenter: center, clock: ReviewClock(instant), userDefaults: defaults)
        await engine.evaluateThresholds(for: [snapshot()])
        XCTAssertEqual(center.requests.count, 0)
        let bytes = try XCTUnwrap(defaults.data(forKey: "notificationThresholdFiredKeys"))
        let stored = try JSONDecoder().decode(Set<FiredNotificationKey>.self, from: bytes)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.bucketKey, "weekly_all")
        XCTAssertEqual(stored.first?.accountID, "account-a")
        XCTAssertEqual(stored.first?.resetAt, legacy.resetAt)
    }

    func testExpiredThresholdKeysAreDroppedWithoutSnapshots() async throws {
        let expired = FiredNotificationKey(providerID: .claudeCode, windowType: .weekly, threshold: 80,
                                           resetAt: instant.addingTimeInterval(-1))
        defaults.set(try JSONEncoder().encode([expired]), forKey: "notificationThresholdFiredKeys")
        let engine = NotificationEngine(notificationCenter: ReviewNotificationCenter(),
                                        clock: ReviewClock(instant), userDefaults: defaults)
        await engine.evaluateThresholds(for: [])
        let bytes = try XCTUnwrap(defaults.data(forKey: "notificationThresholdFiredKeys"))
        XCTAssertTrue(try JSONDecoder().decode(Set<FiredNotificationKey>.self, from: bytes).isEmpty)
    }

}

private struct ReviewClock: Clock {
    let value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { value }
}

private final class ReviewNotificationCenter: UserNotificationCenter, @unchecked Sendable {
    var requests: [NotificationRequest] = []
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func add(request: NotificationRequest) async throws { requests.append(request) }
}
