import XCTest
@testable import AIUsageDashboardCore

/// Round-trip and edge coverage for the shared `CooldownStore` extracted from the
/// Claude / Cursor usage clients. A fixed `now` keeps every assertion deterministic.
final class CooldownStoreTests: XCTestCase {
    private var tempDirectory: URL!
    // A whole-second instant: the on-disk `.iso8601` encoding has no fractional
    // seconds, so a whole second round-trips exactly.
    private let fixedNow = Date(timeIntervalSince1970: 1_762_000_000)

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

    private func makeStore(filename: String = "cooldown.json") -> (CooldownStore, URL) {
        let url = tempDirectory.appendingPathComponent(filename)
        let now = fixedNow
        return (CooldownStore(cooldownURL: url, now: { now }), url)
    }

    // MARK: - persist / read round-trip

    func testPersistThenReadReturnsClampedUntilAndWritesFile() throws {
        let (store, url) = makeStore()

        try store.persist(duration: 120)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.read()?.until, fixedNow.addingTimeInterval(120))
    }

    func testIsActiveTracksTheRecordedBoundary() throws {
        let (store, _) = makeStore()

        try store.persist(duration: 120) // until == fixedNow + 120

        // Active for any instant strictly before `until`.
        XCTAssertTrue(store.isActive(at: fixedNow))
        XCTAssertTrue(store.isActive(at: fixedNow.addingTimeInterval(119)))
        // The boundary is strict (`until > referenceDate`): at and past `until`, inactive.
        XCTAssertFalse(store.isActive(at: fixedNow.addingTimeInterval(120)))
        XCTAssertFalse(store.isActive(at: fixedNow.addingTimeInterval(121)))
    }

    func testNilDurationUsesDefaultInterval() throws {
        let (store, _) = makeStore()

        try store.persist(duration: nil)

        XCTAssertEqual(store.read()?.until, fixedNow.addingTimeInterval(store.defaultCooldownInterval))
    }

    func testDurationIsClampedToMaximum() throws {
        let (store, _) = makeStore()

        try store.persist(duration: store.maxCooldownInterval + 10_000)

        XCTAssertEqual(store.read()?.until, fixedNow.addingTimeInterval(store.maxCooldownInterval))
    }

    func testNegativeDurationIsClampedToZero() throws {
        let (store, _) = makeStore()

        try store.persist(duration: -30)

        XCTAssertEqual(store.read()?.until, fixedNow)
    }

    func testReadReturnsNilWhenNoFileExists() {
        let (store, _) = makeStore()

        XCTAssertNil(store.read())
        XCTAssertFalse(store.isActive(at: fixedNow.addingTimeInterval(1_000)))
    }

    // MARK: - record: swallow-but-log on write failure

    func testRecordWriteFailureIsSwallowedNotThrown() {
        // A cooldown URL nested under an existing *regular file* can't have its parent
        // directory created, so the write fails. `record` must log and return, never
        // crash or propagate — a dropped cooldown must not break the fetch.
        let blockingFile = tempDirectory.appendingPathComponent("not-a-directory")
        try? Data("x".utf8).write(to: blockingFile)
        let url = blockingFile.appendingPathComponent("cooldown.json")
        let now = fixedNow
        let store = CooldownStore(cooldownURL: url, now: { now })

        store.record(duration: 120) // must not throw / crash

        XCTAssertNil(store.read())
        XCTAssertFalse(store.isActive(at: fixedNow.addingTimeInterval(1)))
    }

    func testRecordPersistsWhenPathIsWritable() {
        let (store, url) = makeStore()

        store.record(duration: 60)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.read()?.until, fixedNow.addingTimeInterval(60))
    }

    // MARK: - Retry-After parsing

    private func response(retryAfter: String?) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        return HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func testRetryAfterParsesDelaySeconds() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.retryAfter(from: response(retryAfter: "90")), 90)
    }

    func testRetryAfterClampsNegativeDelaySecondsToZero() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.retryAfter(from: response(retryAfter: "-5")), 0)
    }

    func testRetryAfterParsesRFC1123HTTPDate() {
        let (store, _) = makeStore()
        // 120s after fixedNow, formatted as an RFC-1123 HTTP-date.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: fixedNow.addingTimeInterval(120))

        XCTAssertEqual(store.retryAfter(from: response(retryAfter: header)), 120)
    }

    func testRetryAfterIsNilForMissingHeader() {
        let (store, _) = makeStore()
        XCTAssertNil(store.retryAfter(from: response(retryAfter: nil)))
    }

    func testRetryAfterIsNilForUnparseableValue() {
        let (store, _) = makeStore()
        XCTAssertNil(store.retryAfter(from: response(retryAfter: "not-a-date")))
        XCTAssertNil(store.retryAfter(from: response(retryAfter: "   ")))
    }
}
