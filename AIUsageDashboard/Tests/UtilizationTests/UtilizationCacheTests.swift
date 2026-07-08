import XCTest
@testable import AIUsageDashboardCore

final class UtilizationCacheTests: XCTestCase {
    private var tempDirectory: URL!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

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

    // A clock the test drives by hand — no sleeping, no wall-clock flakiness.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(_ start: Date) { current = start }
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(by interval: TimeInterval) { lock.lock(); current += interval; lock.unlock() }
    }

    private func util(
        _ providerID: ProviderID,
        _ percent: Double,
        window: QuotaWindowType = .monthly,
        resetAt: Date? = nil
    ) -> Utilization {
        Utilization(providerID: providerID, window: window, usedPercent: percent,
                    resetAt: resetAt, confidence: .providerReported)
    }

    private func makeCache(_ clock: TestClock, ttl: TimeInterval = 300, cooldown: TimeInterval = 60) -> UtilizationCache {
        UtilizationCache(now: { clock.now }, ttl: ttl, cooldown: cooldown, directory: tempDirectory)
    }

    // MARK: - TTL freshness

    func testFreshReturnsStoredValueBeforeTTL() async {
        let clock = TestClock(t0)
        let cache = makeCache(clock)
        await cache.store([util(.cursor, 40)], for: .cursor)
        clock.advance(by: 100)
        let fresh = await cache.fresh(for: .cursor)
        XCTAssertEqual(fresh?.first?.usedPercent, 40)
    }

    func testFreshExpiresAfterTTL() async {
        let clock = TestClock(t0)
        let cache = makeCache(clock, ttl: 300)
        await cache.store([util(.cursor, 40)], for: .cursor)
        clock.advance(by: 301)
        let fresh = await cache.fresh(for: .cursor)
        XCTAssertNil(fresh)
    }

    func testFreshExpiresEarlyAtResetAt() async {
        // Reset is 60s out but ttl is 300s → the reading must expire at 60s, not 300s.
        let clock = TestClock(t0)
        let cache = makeCache(clock, ttl: 300)
        await cache.store([util(.antigravity, 50, window: .weekly, resetAt: t0.addingTimeInterval(60))],
                          for: .antigravity)
        clock.advance(by: 90) // past reset, before ttl
        let fresh = await cache.fresh(for: .antigravity)
        XCTAssertNil(fresh)
    }

    func testFreshUsesEarliestResetAcrossWindows() async {
        let clock = TestClock(t0)
        let cache = makeCache(clock, ttl: 300)
        await cache.store([
            util(.antigravity, 20, window: .fiveHour, resetAt: t0.addingTimeInterval(30)),
            util(.antigravity, 70, window: .weekly, resetAt: t0.addingTimeInterval(600))
        ], for: .antigravity)
        clock.advance(by: 45) // past the earliest (5h) reset
        let fresh = await cache.fresh(for: .antigravity)
        XCTAssertNil(fresh)
    }

    // MARK: - Last-good stale serving

    func testLastGoodSurvivesTTLExpiry() async {
        let clock = TestClock(t0)
        let cache = makeCache(clock, ttl: 300)
        await cache.store([util(.cursor, 40)], for: .cursor)
        clock.advance(by: 301)
        let fresh = await cache.fresh(for: .cursor)
        XCTAssertNil(fresh)                                          // fresh gone
        let stale = await cache.lastGood(for: .cursor)
        XCTAssertEqual(stale?.first?.usedPercent, 40)               // stale kept
    }

    func testLastGoodPersistsAcrossInstances() async {
        let clock = TestClock(t0)
        let cache1 = makeCache(clock)
        await cache1.store([util(.cursor, 55)], for: .cursor)

        // A brand-new instance (simulating app relaunch) reads the sidecar.
        let cache2 = makeCache(clock)
        let loaded = await cache2.lastGood(for: .cursor)
        XCTAssertEqual(loaded?.first?.usedPercent, 55)
    }

    // MARK: - Global 429 cooldown (the shared-state behavior)

    func testRateLimitSetsGlobalCooldownObservedByOtherCaller() async {
        let clock = TestClock(t0)
        // One shared cache instance = the global marker every surface consults.
        let cache = makeCache(clock, cooldown: 60)
        await cache.store([util(.cursor, 40)], for: .cursor)

        // Caller A hits a 429.
        await cache.noteRateLimited()

        // Caller B (same instance) must observe the cooldown and serve stale — no error.
        let cooling = await cache.isCoolingDown()
        XCTAssertTrue(cooling)
        let stale = await cache.lastGood(for: .cursor)
        XCTAssertEqual(stale?.first?.usedPercent, 40)
    }

    func testCooldownClearsAfterInterval() async {
        let clock = TestClock(t0)
        let cache = makeCache(clock, cooldown: 60)
        await cache.noteRateLimited()
        let during = await cache.isCoolingDown()
        XCTAssertTrue(during)
        clock.advance(by: 61)
        let after = await cache.isCoolingDown()
        XCTAssertFalse(after)
    }

    func testCooldownRespectsRetryAfter() async {
        let clock = TestClock(t0)
        let cache = makeCache(clock, cooldown: 60)
        await cache.noteRateLimited(retryAfter: 120) // server said wait longer than the default
        clock.advance(by: 90)
        let stillCooling = await cache.isCoolingDown() // default 60 would have cleared; 120 has not
        XCTAssertTrue(stillCooling)
        clock.advance(by: 31)
        let cleared = await cache.isCoolingDown()
        XCTAssertFalse(cleared)
    }

    func testNotCoolingDownInitially() async {
        let cache = makeCache(TestClock(t0))
        let cooling = await cache.isCoolingDown()
        XCTAssertFalse(cooling)
        let remaining = await cache.cooldownRemaining()
        XCTAssertNil(remaining)
    }

    // MARK: - Security invariant (no token ever lands on disk)

    func testSidecarStoresPercentagesNotTokens() async throws {
        let clock = TestClock(t0)
        let cache = makeCache(clock)
        await cache.store([util(.cursor, 40, resetAt: t0)], for: .cursor)

        let fileURL = tempDirectory.appendingPathComponent("utilization-cache.json")
        let contents = try String(contentsOf: fileURL, encoding: .utf8).lowercased()
        XCTAssertTrue(contents.contains("usedpercent"))
        for forbidden in ["token", "bearer", "csrf", "authorization", "secret"] {
            XCTAssertFalse(contents.contains(forbidden), "sidecar leaked `\(forbidden)`")
        }
    }
}
