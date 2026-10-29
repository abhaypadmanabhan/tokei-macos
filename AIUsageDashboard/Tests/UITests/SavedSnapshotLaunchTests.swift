import XCTest
@testable import AIUsageDashboardCore

/// WP-3 AC1: a launch shows the last run's numbers at once, says how old they are, and
/// never passes a saved quota reading from before its reset off as current.
@MainActor
final class SavedSnapshotLaunchTests: XCTestCase {
    /// Wednesday 2026-10-28 09:00:00 UTC.
    private static let now = Date(timeIntervalSince1970: 1_793_178_000)
    private static let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedSnapshotLaunchTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func savedClaude() -> ProviderSnapshot {
        let weekly = QuotaWindow(
            providerID: .claudeCode, type: .weekly, used: 64, limit: 100,
            resetAt: Self.now.addingTimeInterval(2 * 86_400),
            confidence: .providerReported, source: "test"
        )
        let session = QuotaWindow(
            providerID: .claudeCode, type: .session, used: 97, limit: 100,
            resetAt: Self.eightDaysAgo.addingTimeInterval(3_600),
            confidence: .providerReported, source: "test"
        )
        return ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            quotaWindows: [session, weekly],
            todayUsage: TokenUsage(inputTokens: 338_000_000, confidence: .exact),
            weekUsage: TokenUsage(inputTokens: 7_200_000_000, confidence: .exact),
            lastSyncedAt: Self.eightDaysAgo
        )
    }

    func testLaunchShowsSavedNumbersWithTheirAge() async {
        let store = UsageStore(directory: directory)
        await store.save(snapshots: [savedClaude()])
        let model = DashboardViewModel(store: store, now: { Self.now })

        await model.loadSavedSnapshots()

        XCTAssertEqual(model.snapshots.map(\.providerID), [.claudeCode])
        XCTAssertEqual(model.snapshots.first?.todayUsage.totalTokens, 338_000_000)
        XCTAssertTrue(model.showingSavedSnapshots)
        XCTAssertEqual(model.savedSnapshotsDate, Self.eightDaysAgo)
    }

    /// The 97% session reading reset seven days ago: shown as unknown, and the 64% weekly
    /// (still inside its window) is what the tightest reading may use.
    func testSavedReadingPastItsResetIsUnknown() async throws {
        let store = UsageStore(directory: directory)
        await store.save(snapshots: [savedClaude()])
        let model = DashboardViewModel(store: store, now: { Self.now })

        await model.loadSavedSnapshots()

        let windows = try XCTUnwrap(model.snapshots.first?.quotaWindows)
        let session = try XCTUnwrap(windows.first { $0.type == .session })
        XCTAssertNil(session.used)
        XCTAssertNil(session.resetAt)
        XCTAssertNotEqual(session.confidence, .providerReported)
        XCTAssertEqual(windows.first { $0.type == .weekly }?.used, 64)
        XCTAssertEqual(model.tightestAccountPressure?.usedPercent, 64)
    }

    /// Live numbers that are already on screen are never replaced by older saved ones.
    func testSavedNumbersNeverReplaceLiveOnes() async {
        let store = UsageStore(directory: directory)
        await store.save(snapshots: [savedClaude()])
        let model = DashboardViewModel(store: store, now: { Self.now })
        let live = ProviderSnapshot(
            providerID: .codex, displayName: "Codex", authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 5, confidence: .exact),
            weekUsage: TokenUsage(inputTokens: 5, confidence: .exact)
        )
        model.snapshots = [live]

        await model.loadSavedSnapshots()

        XCTAssertEqual(model.snapshots.map(\.providerID), [.codex])
        XCTAssertFalse(model.showingSavedSnapshots)
    }

    /// The menu bar cannot say "saved on Tue 20 Oct", so it must not show that day's total
    /// as today's; a snapshot saved earlier today is still today's.
    func testTodayIsUnknownOnlyForAnEarlierDaysSave() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let store = UsageStore(directory: directory)
        await store.save(snapshots: [savedClaude()])
        let model = DashboardViewModel(store: store, calendar: calendar, now: { Self.now })
        XCTAssertFalse(model.todayIsUnknown)
        await model.loadSavedSnapshots()
        XCTAssertTrue(model.todayIsUnknown)
    }

    func testTodayIsKnownWhenSavedEarlierToday() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let earlierToday = Self.now.addingTimeInterval(-3_600)
        let store = UsageStore(directory: directory)
        await store.save(snapshots: [ProviderSnapshot(
            providerID: .codex, displayName: "Codex", authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 5, confidence: .exact),
            weekUsage: TokenUsage(inputTokens: 5, confidence: .exact),
            lastSyncedAt: earlierToday
        )])
        let model = DashboardViewModel(store: store, calendar: calendar, now: { Self.now })
        await model.loadSavedSnapshots()
        XCTAssertTrue(model.showingSavedSnapshots)
        XCTAssertFalse(model.todayIsUnknown)
    }

    func testEmptyStoreLeavesTheLoadingState() async {
        let model = DashboardViewModel(store: UsageStore(directory: directory), now: { Self.now })
        await model.loadSavedSnapshots()
        XCTAssertTrue(model.snapshots.isEmpty)
        XCTAssertFalse(model.showingSavedSnapshots)
    }

    // MARK: Words

    func testAgeWords() {
        let now = Self.now
        XCTAssertEqual(SavedAgeCopy.ago(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(SavedAgeCopy.ago(now.addingTimeInterval(-4 * 60), now: now), "4 min ago")
        XCTAssertEqual(SavedAgeCopy.ago(now.addingTimeInterval(-3 * 3_600 - 59), now: now), "3 h ago")
        XCTAssertEqual(SavedAgeCopy.ago(now.addingTimeInterval(-86_400), now: now), "1 day ago")
        XCTAssertEqual(SavedAgeCopy.ago(Self.eightDaysAgo, now: now), "8 days ago")
    }

    func testStatusLine() {
        XCTAssertEqual(
            SavedAgeCopy.statusLine(savedAt: Self.eightDaysAgo, updating: true, now: Self.now),
            "Saved 8 days ago · updating…"
        )
        XCTAssertEqual(
            SavedAgeCopy.statusLine(savedAt: Self.eightDaysAgo, updating: false, now: Self.now),
            "Saved 8 days ago"
        )
        let unknownAge = SavedAgeCopy.statusLine(savedAt: nil, updating: true, now: Self.now)
        XCTAssertEqual(unknownAge, "Saved earlier · updating…")
    }

    /// A snapshot saved on Tue 20 Oct describes that day's "today", so the hero says so.
    func testSavedTodayNamesItsDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        let eightDays = SavedAgeCopy.dayPhrase(savedAt: Self.eightDaysAgo, now: Self.now, calendar: calendar)
        XCTAssertEqual(eightDays, "on Tue 20 Oct")
        XCTAssertEqual(
            SavedAgeCopy.dayPhrase(savedAt: Self.now.addingTimeInterval(-3_600), now: Self.now, calendar: calendar),
            "today"
        )
    }
}
