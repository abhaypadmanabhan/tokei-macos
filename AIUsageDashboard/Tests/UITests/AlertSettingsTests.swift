import XCTest
@testable import AIUsageDashboardCore

/// WP-3 AC7: the Settings threshold editor writes exactly the §4 key and value the
/// notification engine reads.
final class AlertSettingsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "wp3.alerts.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEditorWritesTheExactKeyAndValue() {
        let typed = AlertSettings.parse("95, 70")
        AlertSettings.setThresholds(typed, for: .claudeCode, defaults: defaults)
        XCTAssertEqual(defaults.array(forKey: "notificationThresholds.claude_code") as? [Int], [70, 95])
        XCTAssertNil(defaults.object(forKey: "notificationThresholds.codex"))
        XCTAssertEqual(AlertSettings.thresholds(for: .claudeCode, defaults: defaults), [70, 95])
    }

    func testUnsetReadsTheDefault() {
        XCTAssertEqual(AlertSettings.thresholds(for: .cursor, defaults: defaults), [80, 95])
    }

    func testBlankFieldClearsBackToTheDefault() {
        AlertSettings.setThresholds([60], for: .cursor, defaults: defaults)
        AlertSettings.setThresholds(AlertSettings.parse(""), for: .cursor, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "notificationThresholds.cursor"))
        XCTAssertEqual(AlertSettings.thresholds(for: .cursor, defaults: defaults), [80, 95])
    }

    func testParseAcceptsCommasSpacesAndPercentSigns() {
        XCTAssertEqual(AlertSettings.parse("80, 95"), [80, 95])
        XCTAssertEqual(AlertSettings.parse("50% 75% 90%"), [50, 75, 90])
        XCTAssertEqual(AlertSettings.parse("90,90,50"), [50, 90])
    }

    func testParseRejectsWhatTheEngineCannotUse() {
        XCTAssertNil(AlertSettings.parse("0, 50"))
        XCTAssertNil(AlertSettings.parse("101"))
        XCTAssertNil(AlertSettings.parse("10, 20, 30, 40, 50"))
        XCTAssertNil(AlertSettings.parse("eighty"))
    }

    func testAStoredValueOutOfRangeReadsAsTheDefault() {
        defaults.set([0, 150], forKey: "notificationThresholds.gemini")
        XCTAssertEqual(AlertSettings.thresholds(for: .gemini, defaults: defaults), [80, 95])
    }

    func testPredictiveWarningsKeyMatchesTheContract() {
        XCTAssertEqual(AlertSettings.predictiveWarningsKey, "predictiveQuotaWarningsEnabled")
    }
}
