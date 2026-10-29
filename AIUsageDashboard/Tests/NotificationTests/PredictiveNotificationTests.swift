import UserNotifications
import XCTest
@testable import AIUsageDashboardCore

final class PredictiveNotificationTests: XCTestCase {
    private let suite = FileManager.default.temporaryDirectory
        .appendingPathComponent("ai.AIUsageDashboard.NotificationEngineTests.predictive").path
    private var defaults: UserDefaults!
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
        defaults = nil
        let plist = URL(fileURLWithPath: suite + ".plist")
        try? FileManager.default.removeItem(at: plist)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path))
        defaults = nil
    }

    private func snapshot(used: Double = 75, reset: Date? = nil, bucket: String = "weekly_all") -> ProviderSnapshot {
        let window = QuotaWindow(
            providerID: .claudeCode, type: .weekly, used: used, limit: 100,
            resetAt: reset ?? instant.addingTimeInterval(12 * 3600), confidence: .providerReported,
            source: "fixture", bucketKey: bucket, windowDuration: 24 * 3600
        )
        return ProviderSnapshot(providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
                                quotaWindows: [window], todayUsage: .unavailable, weekUsage: .unavailable)
    }

    func testPredictiveWarningFiresOncePerBucketAndResetAndSurvivesRestart() async {
        let clock = NotificationTestClock(instant)
        let center = RecordingNotificationCenter()
        let engine = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        await engine.evaluateThresholds(for: [snapshot()])
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.requests.first?.body.hasPrefix("Claude Code weekly runs out around ") == true)
        XCTAssertTrue(center.requests.first?.body.hasSuffix(", 8 h before it resets.") == true)
        await engine.evaluateThresholds(for: [snapshot(used: 70)])
        let reloaded = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        await reloaded.evaluateThresholds(for: [snapshot()])
        XCTAssertEqual(center.requests.count, 1)
        await reloaded.evaluateThresholds(for: [snapshot(bucket: "weekly_scoped:model")])
        XCTAssertEqual(center.requests.count, 2)
        clock.set(instant.addingTimeInterval(24 * 3600))
        await reloaded.evaluateThresholds(for: [snapshot(reset: instant.addingTimeInterval(36 * 3600))])
        XCTAssertEqual(center.requests.count, 3)
    }

    func testPredictiveToggleAndFifteenMinuteMinimum() async {
        let center = RecordingNotificationCenter()
        let clock = NotificationTestClock(instant)
        defaults.set(false, forKey: "predictiveQuotaWarningsEnabled")
        let engine = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        await engine.evaluateThresholds(for: [snapshot()])
        XCTAssertTrue(center.requests.isEmpty)
        defaults.set(true, forKey: "predictiveQuotaWarningsEnabled")
        await engine.evaluateThresholds(for: [snapshot(used: 50.5)])
        XCTAssertTrue(center.requests.isEmpty, "50.5% used at the halfway point runs out less than 15 minutes early")
        await engine.evaluateThresholds(for: [snapshot()])
        XCTAssertEqual(center.requests.count, 1)
    }

    func testResetJitterFiresOnceUntilStoredResetHasPassed() async {
        let clock = NotificationTestClock(instant)
        let center = RecordingNotificationCenter()
        let reset = instant.addingTimeInterval(12 * 3600)
        let engine = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        await engine.evaluateThresholds(for: [snapshot(reset: reset)])
        await engine.evaluateThresholds(for: [snapshot(reset: reset.addingTimeInterval(0.5))])
        XCTAssertEqual(center.requests.count, 1, "half-second reset jitter is still one window")
        let reloaded = NotificationEngine(notificationCenter: center, clock: clock, userDefaults: defaults)
        await reloaded.evaluateThresholds(for: [snapshot(reset: reset.addingTimeInterval(600))])
        XCTAssertEqual(center.requests.count, 1, "ten-minute reset jitter survives an engine restart")
        await reloaded.evaluateThresholds(for: [snapshot(reset: reset.addingTimeInterval(601))])
        XCTAssertEqual(center.requests.count, 1, "a future stored reset cannot re-arm early")
        clock.set(instant.addingTimeInterval(24 * 3600))
        await reloaded.evaluateThresholds(for: [snapshot(reset: instant.addingTimeInterval(36 * 3600))])
        XCTAssertEqual(center.requests.count, 2)
    }

    func testProviderThresholdsUseExactKeyAndInvalidValuesFallBack() async {
        defaults.set([60], forKey: "notificationThresholds.claude_code")
        defaults.set([100], forKey: "notificationThresholds.codex")
        defaults.set(false, forKey: "predictiveQuotaWarningsEnabled")
        let center = RecordingNotificationCenter()
        let engine = NotificationEngine(notificationCenter: center, userDefaults: defaults)
        await engine.evaluateThresholds(for: [snapshot(used: 65)])
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.requests.first?.body.contains("65%") == true)
        defaults.set([0, 101], forKey: "notificationThresholds.claude_code")
        await engine.evaluateThresholds(for: [snapshot(used: 85)])
        XCTAssertEqual(center.requests.count, 2, "invalid configuration must use 80 and 95")
    }

    func testProviderSettingsStaySeparateAndAtMostFourThresholdsAreAccepted() async {
        defaults.set([60], forKey: "notificationThresholds.claude_code")
        defaults.set([100], forKey: "notificationThresholds.codex")
        defaults.set(false, forKey: "predictiveQuotaWarningsEnabled")
        let codex = ProviderSnapshot(
            providerID: .codex, displayName: "Codex", authStatus: .authenticated,
            quotaWindows: [QuotaWindow(providerID: .codex, type: .weekly, used: 70, limit: 100,
                                       confidence: .providerReported, source: "fixture")],
            todayUsage: .unavailable, weekUsage: .unavailable
        )
        let center = RecordingNotificationCenter()
        let engine = NotificationEngine(notificationCenter: center, userDefaults: defaults)
        await engine.evaluateThresholds(for: [codex, snapshot(used: 70)])
        XCTAssertEqual(center.requests.count, 1)
        defaults.set([10, 20, 30, 40, 50], forKey: "notificationThresholds.claude_code")
        await engine.evaluateThresholds(for: [snapshot(used: 85)])
        XCTAssertEqual(center.requests.count, 2)
    }
}

private final class NotificationTestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}

private final class RecordingNotificationCenter: UserNotificationCenter, @unchecked Sendable {
    var requests: [NotificationRequest] = []
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func add(request: NotificationRequest) async throws { requests.append(request) }
}
