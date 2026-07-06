import XCTest
import UserNotifications
@testable import AIUsageDashboardCore

final class NotificationEngineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ai.AIUsageDashboard.NotificationEngineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSnapshot(
        providerID: ProviderID = .codex,
        displayName: String = "OpenAI Codex",
        windowType: QuotaWindowType = .weekly,
        used: Double,
        limit: Double,
        resetAt: Date? = nil,
        confidence: MetricConfidence = .providerReported
    ) -> ProviderSnapshot {
        let window = QuotaWindow(
            providerID: providerID,
            type: windowType,
            used: used,
            limit: limit,
            resetAt: resetAt,
            confidence: confidence,
            source: "test"
        )
        return ProviderSnapshot(
            providerID: providerID,
            displayName: displayName,
            authStatus: .authenticated,
            quotaWindows: [window],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
    }

    private func makeEngine(
        clock: Clock = SystemClock(),
        center: UserNotificationCenter = FakeNotificationCenter()
    ) -> NotificationEngine {
        NotificationEngine(
            notificationCenter: center,
            clock: clock,
            userDefaults: defaults
        )
    }

    // MARK: - Firing

    func testThresholdCrossingFiresOnce() async {
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let snapshot = makeSnapshot(used: 82, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [snapshot])

        XCTAssertEqual(center.requests.count, 1)
        XCTAssertTrue(center.requests.first?.body.contains("82%") ?? false)
        XCTAssertTrue(center.requestAuthorizationCalled)
    }

    func testNinetyFiveThresholdFiresBoth() async {
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let snapshot = makeSnapshot(used: 96, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [snapshot])

        XCTAssertEqual(center.requests.count, 2)
        XCTAssertTrue(center.requests.allSatisfy { $0.body.contains("96%") })
        XCTAssertTrue(center.requests.allSatisfy { $0.body.contains("OpenAI Codex") })
    }

    func testNoRefireWhileArmed() async {
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let snapshot = makeSnapshot(used: 82, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [snapshot])
        XCTAssertEqual(center.requests.count, 1)

        await engine.evaluateThresholds(for: [snapshot])
        XCTAssertEqual(center.requests.count, 1)
    }

    // MARK: - Re-arm

    func testRearmsAfterResetAtPasses() async {
        let now = Date()
        let resetAt = now.addingTimeInterval(3600)
        let laterClock = FakeClock(nowValue: resetAt.addingTimeInterval(1))
        let center = FakeNotificationCenter()
        let engine = makeEngine(clock: laterClock, center: center)

        let snapshotBefore = makeSnapshot(used: 82, limit: 100, resetAt: resetAt)
        await engine.evaluateThresholds(for: [snapshotBefore])
        XCTAssertEqual(center.requests.count, 1)

        let newReset = resetAt.addingTimeInterval(7200)
        let snapshotAfter = makeSnapshot(used: 85, limit: 100, resetAt: newReset)
        await engine.evaluateThresholds(for: [snapshotAfter])
        XCTAssertEqual(center.requests.count, 2)
    }

    func testRearmsWhenPercentDropsBelowThreshold() async {
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let high = makeSnapshot(used: 82, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [high])
        XCTAssertEqual(center.requests.count, 1)

        let low = makeSnapshot(used: 70, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [low])
        XCTAssertEqual(center.requests.count, 1)

        let highAgain = makeSnapshot(used: 84, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [highAgain])
        XCTAssertEqual(center.requests.count, 2)
    }

    // MARK: - Suppression

    func testDisabledToggleSuppresses() async {
        defaults.set(false, forKey: NotificationEngine.notificationsEnabledKey)
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let snapshot = makeSnapshot(used: 82, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [snapshot])

        XCTAssertEqual(center.requests.count, 0)
        XCTAssertFalse(center.requestAuthorizationCalled)
    }

    func testUnavailableConfidenceIgnored() async {
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let snapshot = makeSnapshot(used: 82, limit: 100, confidence: .unavailable)
        await engine.evaluateThresholds(for: [snapshot])

        XCTAssertEqual(center.requests.count, 0)
    }

    func testMissingLimitSkipsWindow() async {
        let center = FakeNotificationCenter()
        let engine = makeEngine(center: center)

        let window = QuotaWindow(
            providerID: .codex,
            type: .weekly,
            used: 82,
            confidence: .providerReported,
            source: "test"
        )
        let snapshot = ProviderSnapshot(
            providerID: .codex,
            displayName: "OpenAI Codex",
            authStatus: .authenticated,
            quotaWindows: [window],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
        await engine.evaluateThresholds(for: [snapshot])

        XCTAssertEqual(center.requests.count, 0)
    }

    func testAuthorizationDeniedSuppresses() async {
        let center = FakeNotificationCenter()
        center.authorizationGranted = false
        let engine = makeEngine(center: center)

        let snapshot = makeSnapshot(used: 82, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine.evaluateThresholds(for: [snapshot])

        XCTAssertTrue(center.requestAuthorizationCalled)
        XCTAssertEqual(center.requests.count, 0)
    }

    func testPersistenceSurvivesReinit() async {
        let center = FakeNotificationCenter()
        let engine1 = makeEngine(center: center)
        let snapshot = makeSnapshot(used: 82, limit: 100, resetAt: Date().addingTimeInterval(3600))
        await engine1.evaluateThresholds(for: [snapshot])
        XCTAssertEqual(center.requests.count, 1)

        let engine2 = makeEngine(center: center)
        await engine2.evaluateThresholds(for: [snapshot])
        XCTAssertEqual(center.requests.count, 1)
    }

    // MARK: - Pure evaluator

    func testEvaluatorRearmsAfterResetAt() {
        let now = Date()
        let resetAt = now.addingTimeInterval(3600)
        let window = QuotaWindow(
            providerID: .codex,
            type: .weekly,
            used: 82,
            limit: 100,
            resetAt: resetAt,
            confidence: .providerReported,
            source: "test"
        )
        let snapshot = ProviderSnapshot(
            providerID: .codex,
            displayName: "OpenAI Codex",
            authStatus: .authenticated,
            quotaWindows: [window],
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )

        let armedKey = FiredNotificationKey(providerID: .codex, windowType: .weekly, threshold: 80)
        let before = ThresholdEvaluator.evaluate(
            snapshots: [snapshot],
            clock: FakeClock(nowValue: now),
            previouslyFired: []
        )
        XCTAssertEqual(before.notifications.count, 1)
        XCTAssertTrue(before.fired.contains(armedKey))

        let after = ThresholdEvaluator.evaluate(
            snapshots: [snapshot],
            clock: FakeClock(nowValue: resetAt.addingTimeInterval(1)),
            previouslyFired: before.fired
        )
        XCTAssertEqual(after.notifications.count, 1)
        XCTAssertTrue(after.fired.contains(armedKey))
    }
}

// MARK: - Fakes

private struct FakeClock: Clock, Sendable {
    let nowValue: Date
    func now() -> Date { nowValue }
}

private final class FakeNotificationCenter: UserNotificationCenter, @unchecked Sendable {
    var requests: [NotificationRequest] = []
    var authorizationGranted = true
    var requestAuthorizationCalled = false

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCalled = true
        return authorizationGranted
    }

    func add(request: NotificationRequest) async throws {
        requests.append(request)
    }
}
