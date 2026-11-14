import XCTest
import UserNotifications
@testable import AIUsageDashboardCore

final class BurnNotificationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let f = BurnFixtures(zone: "America/Los_Angeles")

    override func setUpWithError() throws {
        suite = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private func engine(_ center: BurnTestCenter, now: Date? = nil) -> NotificationEngine {
        NotificationEngine(notificationCenter: center, clock: BurnTestClock(time: now ?? f.now), userDefaults: defaults)
    }
    private func window(_ type: QuotaWindowType = .fiveHour, unused: Double = 62,
                        inSeconds: TimeInterval = 41 * 60, account: String? = nil,
                        bucket: String = "five", observedAt: Date? = nil) -> ExpiringHeadroom {
        ExpiringHeadroom(providerID: .codex, providerName: "Codex", accountID: account, windowType: type,
                         bucketKey: bucket, usedPercent: 100 - unused, resetAt: f.now.addingTimeInterval(inSeconds),
                         observedAt: observedAt ?? f.now, confidence: .providerReported)
    }
    private func snapshot(windows: [ExpiringHeadroom] = [], moments: [BurnMoment] = [], recordValue: Double = 10) -> BurnSnapshot {
        let empty = BurnSnapshot.empty(now: f.now, calendar: f.calendar)
        return BurnSnapshot(generatedAt: f.now, today: empty.today, streak: empty.streak, expiring: windows,
                            records: BurnRecords(bestDay: BurnRecord(kind: .bestDay, value: recordValue, unit: .usd, achievedAt: f.day(0)),
                                                 bestWeek: nil, bestMonthMultiple: nil, longestStreak: nil),
                            leaderboard: [], badges: [], recentWindows: [], tier: nil, monthValueMultiple: nil, moments: moments)
    }

    func testExpiringFirstThenBadgeInsideOneQuietCapAndNoDuplicatesAfterRestart() async {
        let center = BurnTestCenter()
        let snapshot = snapshot(windows: [window()], moments: [.badge(.streak7), .record(.bestDay)])
        let first = engine(center)
        await first.evaluateBurn(snapshot, calendar: f.calendar)
        let sent = await center.requests
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].body, "Codex 5-hour window: 62% left, resets in 41 min. Burn it before it's gone.")
        XCTAssertEqual(sent[1].body, "New badge: Week on fire. Seven days at your goal.")
        XCTAssertTrue(sent.allSatisfy { !$0.sound })
        await first.evaluateBurn(snapshot, calendar: f.calendar)
        await engine(center).evaluateBurn(snapshot, calendar: f.calendar)
        let after = await center.requests
        XCTAssertEqual(after.count, 2)
    }

    func testPerWindowInstanceIncludesAccountBucketAndReset() async {
        let center = BurnTestCenter()
        let first = engine(center)
        await first.evaluateBurn(snapshot(windows: [window(account: "a")]), calendar: f.calendar)
        await first.evaluateBurn(snapshot(windows: [window(account: "a")]), calendar: f.calendar)
        await first.evaluateBurn(snapshot(windows: [window(account: "b")]), calendar: f.calendar)
        let sent = await center.requests
        XCTAssertEqual(sent.count, 2)
        XCTAssertNotEqual(sent[0].identifier, sent[1].identifier)
        // Fresh local day gets its own cap, including across the DST boundary.
        let tomorrow = f.calendar.date(byAdding: .day, value: 1, to: f.now)!
        let nextWindow = ExpiringHeadroom(providerID: .codex, providerName: "Codex", accountID: "a", windowType: .fiveHour,
                                          bucketKey: "five", usedPercent: 10, resetAt: tomorrow.addingTimeInterval(600),
                                          observedAt: tomorrow, confidence: .exact)
        await engine(center, now: tomorrow).evaluateBurn(snapshot(windows: [nextWindow]), calendar: f.calendar)
        let after = await center.requests
        XCTAssertEqual(after.count, 3)
        XCTAssertNotEqual(after[0].identifier, after[2].identifier)
    }

    func testBurnAndMasterSwitchesSuppressWithoutAuthorizationAndUnsetEnables() async {
        for key in [BurnNudgePolicy.enabledKey, NotificationEngine.notificationsEnabledKey] {
            let center = BurnTestCenter()
            defaults.set(false, forKey: key)
            await engine(center).evaluateBurn(snapshot(windows: [window()]), calendar: f.calendar)
            let requests = await center.requests
            let asked = await center.authorizationCount
            XCTAssertTrue(requests.isEmpty)
            XCTAssertEqual(asked, 0)
            defaults.removeObject(forKey: key)
        }
        let center = BurnTestCenter()
        await engine(center).evaluateBurn(snapshot(windows: [window()]), calendar: f.calendar)
        let requests = await center.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testExactHorizonAndUnusedThresholdsAndPaidWindowsNeverNotify() async {
        let cases: [(QuotaWindowType, Double, TimeInterval, Bool)] = [
            (.fiveHour, 40, 3600, true), (.session, 40, 3600, true), (.daily, 40, 3600, true),
            (.fiveHour, 39.999, 600, false), (.daily, 50, 3601, false),
            (.weekly, 40, 21600, true), (.monthly, 40, 21600, true), (.weekly, 50, 21601, false),
            (.fiveHour, 62, 0, false), (.credits, 99, 600, false), (.perModel, 99, 600, false),
            (.lifetime, 99, 600, false)
        ]
        for (type, unused, seconds, fires) in cases {
            defaults.removePersistentDomain(forName: suite)
            let center = BurnTestCenter()
            await engine(center).evaluateBurn(snapshot(windows: [window(type, unused: unused, inSeconds: seconds)]), calendar: f.calendar)
            let requests = await center.requests
            XCTAssertEqual(requests.count, fires ? 1 : 0, "\(type) \(unused) \(seconds)")
            XCTAssertFalse(requests.contains { $0.body.lowercased().contains("credits") || $0.body.lowercased().contains("overage") })
        }
    }

    func testBadgeAndRecordEachNotifyOnceWithinCap() async {
        let center = BurnTestCenter()
        let engine = engine(center)
        let snapshot = snapshot(moments: [.badge(.millionDay), .record(.bestDay), .tierUp(.maxxing)])
        await engine.evaluateBurn(snapshot, calendar: f.calendar)
        await engine.evaluateBurn(snapshot, calendar: f.calendar)
        let requests = await center.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].body.hasPrefix("New badge:"))
        XCTAssertTrue(requests[1].body.hasPrefix("New record:"))
    }

    func testDenialAndFailedDeliveryDoNotConsumeCap() async {
        let center = BurnTestCenter()
        await center.configure(granted: false, fails: false)
        let engine = engine(center)
        let snapshot = snapshot(windows: [window()])
        await engine.evaluateBurn(snapshot, calendar: f.calendar)
        await center.configure(granted: true, fails: true)
        await engine.evaluateBurn(snapshot, calendar: f.calendar)
        await center.configure(granted: true, fails: false)
        await engine.evaluateBurn(snapshot, calendar: f.calendar)
        let requests = await center.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testRecordNudgeIsOncePerPeriodDespiteValueGrowth() async {
        let center = BurnTestCenter()
        let engine = engine(center)
        await engine.evaluateBurn(snapshot(moments: [.record(.bestDay)], recordValue: 10), calendar: f.calendar)
        await engine.evaluateBurn(snapshot(moments: [.record(.bestDay)], recordValue: 11), calendar: f.calendar)
        let sent = await center.requests
        XCTAssertEqual(sent.count, 1)
    }

    func testResetJitterSuppressesNudgesAcrossRestartButNextWindowCanNotify() async {
        let center = BurnTestCenter()
        await engine(center).evaluateBurn(snapshot(windows: [window()]), calendar: f.calendar)
        await engine(center, now: f.now.addingTimeInterval(300)).evaluateBurn(
            snapshot(windows: [window(inSeconds: 41 * 60 + 1)]), calendar: f.calendar)
        await engine(center, now: f.now.addingTimeInterval(600)).evaluateBurn(
            snapshot(windows: [window(inSeconds: 41 * 60 + 600)]), calendar: f.calendar)
        let jittered = await center.requests
        XCTAssertEqual(jittered.count, 1)
        let next = f.now.addingTimeInterval(5 * 3_600)
        await engine(center, now: next).evaluateBurn(
            snapshot(windows: [window(inSeconds: 5 * 3_600 + 41 * 60, observedAt: next)]), calendar: f.calendar)
        let sent = await center.requests
        XCTAssertEqual(sent.count, 2)
    }

    func testBurnAuthorizesAlertAndSoundButDeliversSilently() async {
        let center = BurnTestCenter()
        await engine(center).evaluateBurn(snapshot(windows: [window()]), calendar: f.calendar)
        let options = await center.authorizationOptions
        XCTAssertEqual(options, [[.alert, .sound]])
        let sent = await center.requests
        XCTAssertEqual(sent.count, 1)
        XCTAssertFalse(sent[0].sound)
    }

    func testConcurrentEvaluationsCannotExceedCap() async {
        let center = BurnTestCenter()
        let engine = engine(center)
        let snapshot = snapshot(windows: [window()], moments: [.badge(.millionDay), .record(.bestDay)])
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { await engine.evaluateBurn(snapshot, calendar: self.f.calendar) } }
        }
        let requests = await center.requests
        XCTAssertEqual(requests.count, 2)
    }
}

private struct BurnTestClock: Clock {
    let time: Date
    func now() -> Date { time }
}

private actor BurnTestCenter: UserNotificationCenter {
    private(set) var requests: [NotificationRequest] = []
    private(set) var authorizationCount = 0
    private(set) var authorizationOptions: [UNAuthorizationOptions] = []
    private var granted = true
    private var fails = false
    func configure(granted: Bool, fails: Bool) { self.granted = granted; self.fails = fails }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationCount += 1
        authorizationOptions.append(options)
        await Task.yield()
        return granted
    }
    func add(request: NotificationRequest) async throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        requests.append(request)
    }
}
