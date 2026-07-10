import XCTest
@testable import AIUsageDashboardCore

final class QuotaSeriesStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testAppendReloadRoundTripAndReadFilters() async throws {
        let clock = TestClock(isoDate("2026-07-09T12:00:00Z"))
        let store = QuotaSeriesStore(
            now: clock.now,
            directory: tempDirectory,
            retentionLimit: 10
        )

        await store.append(from: [snapshot(windows: [
            window(.weekly, providerID: .codex, used: 25, limit: 100, sampledBucket: "codex-weekly")
        ])])
        clock.set(isoDate("2026-07-09T12:05:00Z"))
        await store.append(from: [snapshot(windows: [
            window(.weekly, providerID: .codex, used: 35, limit: 100, sampledBucket: "codex-weekly"),
            window(.session, providerID: .codex, used: 5, limit: 100, sampledBucket: "codex-session"),
            window(.weekly, providerID: .cursor, used: 40, limit: 100, sampledBucket: "cursor-weekly")
        ])])

        let reloaded = QuotaSeriesStore(directory: tempDirectory, retentionLimit: 10)
        let samples = await reloaded.samples(
            for: .codex,
            windowType: .weekly,
            since: isoDate("2026-07-09T12:01:00Z")
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].providerID, .codex)
        XCTAssertEqual(samples[0].windowType, .weekly)
        XCTAssertEqual(samples[0].bucketKey, "codex-weekly")
        XCTAssertEqual(samples[0].usedPercent, 35, accuracy: 0.0001)
        XCTAssertEqual(samples[0].used, 35, accuracy: 0.0001)
        XCTAssertEqual(samples[0].limit, 100, accuracy: 0.0001)
        XCTAssertEqual(samples[0].sampledAt, isoDate("2026-07-09T12:05:00Z"))
    }

    func testConsecutiveIdenticalSamplesCollapse() async {
        let clock = TestClock(isoDate("2026-07-09T12:00:00Z"))
        let store = QuotaSeriesStore(
            now: clock.now,
            directory: tempDirectory,
            retentionLimit: 10
        )
        let quotaWindow = window(.weekly, providerID: .codex, used: 25, limit: 100, sampledBucket: "codex-weekly")

        await store.append(from: [snapshot(windows: [quotaWindow])])
        clock.set(isoDate("2026-07-09T12:05:00Z"))
        await store.append(from: [snapshot(windows: [quotaWindow])])

        let samples = await store.samples(for: .codex, windowType: .weekly, since: nil)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].sampledAt, isoDate("2026-07-09T12:00:00Z"))
    }

    func testRetentionLimitKeepsNewestSamples() async {
        let clock = TestClock(isoDate("2026-07-09T12:00:00Z"))
        let store = QuotaSeriesStore(
            now: clock.now,
            directory: tempDirectory,
            retentionLimit: 3
        )

        for percent in [10.0, 20.0, 30.0, 40.0, 50.0] {
            await store.append(from: [snapshot(windows: [
                window(.weekly, providerID: .codex, used: percent, limit: 100, sampledBucket: "codex-weekly")
            ])])
            clock.advance(by: 60)
        }

        let samples = await store.samples(for: .codex, windowType: .weekly, since: nil)
        XCTAssertEqual(samples.map(\.usedPercent), [30, 40, 50])
    }

    func testAtomicWriteSurvivesLeftoverTempFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("quota-series.json")
        let tempURL = tempDirectory.appendingPathComponent(".quota-series.json.crash.tmp")
        try quotaSeriesFixture.write(to: fileURL, atomically: true, encoding: .utf8)
        try #"{"samples":["partial"]}"#.write(to: tempURL, atomically: true, encoding: .utf8)

        let store = QuotaSeriesStore(directory: tempDirectory, retentionLimit: 10)
        let existing = await store.samples(for: .codex, windowType: .weekly, since: nil)

        XCTAssertEqual(existing.count, 1)
        XCTAssertEqual(existing[0].usedPercent, 25, accuracy: 0.0001)
        XCTAssertEqual(existing[0].sampledAt, isoDate("2026-07-09T12:00:00Z"))
    }

    private func snapshot(windows: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: windows.first?.providerID ?? .codex,
            displayName: "Test",
            authStatus: .authenticated,
            quotaWindows: windows,
            todayUsage: .unavailable,
            weekUsage: .unavailable
        )
    }

    private func window(
        _ type: QuotaWindowType,
        providerID: ProviderID,
        used: Double,
        limit: Double,
        sampledBucket: String
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: providerID,
            type: type,
            used: used,
            limit: limit,
            remaining: limit - used,
            resetAt: isoDate("2026-07-10T00:00:00Z"),
            confidence: .providerReported,
            source: "test",
            bucketKey: sampledBucket
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private var quotaSeriesFixture: String {
        """
        {
          "version" : 1,
          "samples" : [
            {
              "providerID" : "codex",
              "windowType" : "weekly",
              "bucketKey" : "codex-weekly",
              "usedPercent" : 25,
              "used" : 25,
              "limit" : 100,
              "resetAt" : "2026-07-10T00:00:00Z",
              "sampledAt" : "2026-07-09T12:00:00Z"
            }
          ]
        }
        """
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Date) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}
