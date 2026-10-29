import XCTest
@testable import AIUsageDashboardCore

final class CursorPoolTests: XCTestCase {
    func testCapturedSummarySeparatesCursorAndOtherModels() throws {
        let summary = try XCTUnwrap(CursorUsageSummary.decode(Data(CursorFixtures.usageSummary.utf8)))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let windows = summary.quotaWindows(observedAt: now)
        XCTAssertEqual(windows.map(\.label), ["Cursor models", "Other models"])
        XCTAssertEqual(windows.map(\.used), [40, 45])
        XCTAssertEqual(windows.map(\.bucketKey), ["cursor_auto", "cursor_api"])
        XCTAssertEqual(windows.map(\.observedAt), [now, now])
    }

    func testSummaryWithoutBothPoolsKeepsOverallFallback() throws {
        let summary = try XCTUnwrap(CursorUsageSummary.decode(Data(CursorFixtures.usageSummaryCentsOnly.utf8)))
        let windows = summary.quotaWindows(observedAt: nil)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.used, 25)
    }
}
