import XCTest
@testable import AIUsageDashboardCore

/// `-TokeiProofFixture demo` (Debug only) feeds the website captures, so nothing in it may
/// identify this Mac or a person: no home-directory path, no `@` (e-mail addresses, and the
/// `<model>@<tier>` keys that carry real model routing), and every screen gets data.
final class DemoFixtureTests: XCTestCase {
    /// Friday 2026-11-13 15:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_582_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Every string reachable from `value`, through structs, enums, optionals, arrays and
    /// dictionaries, so a field added to a model later is checked without editing this test.
    private func strings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let url = value as? URL { return [url.path] }
        return Mirror(reflecting: value).children.flatMap { strings(in: $0.value) }
    }

    func testTheFixtureHoldsNoHomePathNoAtSignAndNoUserName() {
        let all = strings(in: DemoFixture.snapshots(now: now, calendar: calendar))
            + DemoFixture.defaults.keys + DemoFixture.defaults.values.flatMap { strings(in: $0) }
            + DemoFixture.paceBaselines.keys
        XCTAssertGreaterThan(all.count, 50, "the walk must reach the model keys and labels")
        let home = NSHomeDirectory()
        let user = NSUserName()
        for string in all {
            XCTAssertFalse(string.contains(home), "home path in \(string)")
            XCTAssertFalse(string.contains("/Users/"), "user path in \(string)")
            XCTAssertFalse(string.contains("@"), "@ in \(string)")
            XCTAssertFalse(string.localizedCaseInsensitiveContains(user), "user name in \(string)")
        }
    }

    func testEveryScreenHasDataToShow() {
        let snapshots = DemoFixture.snapshots(now: now, calendar: calendar)
        XCTAssertEqual(snapshots.map(\.providerID), [.claudeCode, .codex, .cursor, .gemini])
        for snapshot in snapshots {
            XCTAssertGreaterThan(snapshot.todayUsage.totalTokens ?? 0, 0, "\(snapshot.providerID) today")
            XCTAssertGreaterThanOrEqual(snapshot.dailyTotals?.count ?? 0, 30, "\(snapshot.providerID) trend")
            XCTAssertFalse(snapshot.hourlyTotals?.isEmpty ?? true, "\(snapshot.providerID) heatmap")
            XCTAssertFalse(snapshot.dailyModelUsage?.isEmpty ?? true, "\(snapshot.providerID) value by model")
        }
        XCTAssertEqual(Set(UtilizationEngine.utilizations(from: snapshots).map(\.providerID)),
                       [.claudeCode, .codex, .cursor, .gemini])
    }

    /// The captures show a full route: a recommendation with its reason, a runner-up, and a
    /// plan to avoid, with no stale reading.
    func testTheRouteShowsARecommendationARunnerUpAndAPlanToAvoid() {
        let plan = RoutePlan.make(snapshots: DemoFixture.snapshots(now: now, calendar: calendar), now: now)
        XCTAssertEqual(plan.rows.map(\.providerID), [.codex, .claudeCode, .gemini, .cursor])
        XCTAssertEqual(plan.recommendation?.providerID, .codex)
        XCTAssertNotNil(plan.recommendation?.expiringAt)
        XCTAssertEqual(plan.rows.last?.disposition, .avoid)
        XCTAssertTrue(plan.unknown.isEmpty)
    }

    /// Sync now, a retry or any other refresh during a demo run shows the demo again: the
    /// demo view model's engine reads only the demo agents.
    @MainActor
    func testARefreshDuringTheDemoShowsTheDemoAgain() async {
        let model = DemoFixture.viewModel()
        await model.refresh()
        XCTAssertEqual(Set(model.snapshots.map(\.providerID)), [.claudeCode, .codex, .cursor, .gemini])
        XCTAssertEqual(model.snapshots.first { $0.providerID == .codex }?.quotaWindows.first?.source, "demo fixture")
        XCTAssertNil(model.errorMessage)
    }

    /// The argument domain is never saved: installing the demo settings changes what this run
    /// reads and leaves the stored preferences alone.
    func testInstallingTheDemoSettingsLeavesSavedPreferencesAlone() throws {
        let suite = "DemoFixtureTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set(42.0, forKey: "maxxer.planCost.claude_code")
        let before = store.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { store.setVolatileDomain(before, forName: UserDefaults.argumentDomain) }

        DemoFixture.installDefaults(into: store)

        XCTAssertEqual(store.double(forKey: "maxxer.planCost.claude_code"), 100)
        XCTAssertEqual(store.persistentDomain(forName: suite)?["maxxer.planCost.claude_code"] as? Double, 42)
    }
}
