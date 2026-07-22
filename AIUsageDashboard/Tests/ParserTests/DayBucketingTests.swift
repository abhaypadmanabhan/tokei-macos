import XCTest
@testable import AIUsageDashboardCore

/// Edge coverage for the UTC-instant → `Calendar.startOfDay` day-bucketing in
/// `UsageWindows`. Production buckets with `Calendar.current`; these tests pin the
/// calendar's time zone and inject a fixed reference date so the midnight boundary
/// is deterministic on any CI machine, and assert against independently-derived
/// expected buckets (not `startOfDay` re-applied, which would be circular).
final class DayBucketingTests: XCTestCase {
    private func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }

    private func iso(_ value: String) -> Date { JSONLDateParsing.iso8601(value)! }

    private func usage(_ tokens: Int) -> TokenUsage {
        TokenUsage(inputTokens: tokens, confidence: .localParsed)
    }

    /// Two UTC instants on the *same* UTC calendar day (2026-01-15) that straddle
    /// New York local midnight (UTC-5 in January) must fall into two distinct local
    /// day buckets.
    func testInstantsStraddlingLocalMidnightSplitIntoTwoLocalDays() {
        let cal = calendar(timeZoneIdentifier: "America/New_York")
        var windows = UsageWindows(calendar: cal, referenceDate: iso("2026-01-20T12:00:00Z"))

        // 2026-01-14 23:30 EST — belongs to the Jan 14 local day.
        windows.accumulate(usage(30), timestamp: iso("2026-01-15T04:30:00Z"), dailyTotal: 30)
        // 2026-01-15 00:30 EST — belongs to the Jan 15 local day.
        windows.accumulate(usage(70), timestamp: iso("2026-01-15T05:30:00Z"), dailyTotal: 70)

        let dailyTotals = windows.snapshot().dailyTotals
        // Local midnight in UTC: EST is -05:00, so Jan 14 00:00 EST == 2026-01-14T05:00:00Z.
        let jan14Bucket = iso("2026-01-14T05:00:00Z")
        let jan15Bucket = iso("2026-01-15T05:00:00Z")

        XCTAssertEqual(dailyTotals.count, 2)
        XCTAssertEqual(dailyTotals[jan14Bucket], 30)
        XCTAssertEqual(dailyTotals[jan15Bucket], 70)
        XCTAssertNotEqual(jan14Bucket, jan15Bucket)
    }

    /// The boundary is calendar-relative: the very same two instants, bucketed with a
    /// UTC calendar, collapse into one day because both are 2026-01-15 in UTC.
    func testSameInstantsCollapseIntoOneDayUnderUTCCalendar() {
        let cal = calendar(timeZoneIdentifier: "UTC")
        var windows = UsageWindows(calendar: cal, referenceDate: iso("2026-01-20T12:00:00Z"))

        windows.accumulate(usage(30), timestamp: iso("2026-01-15T04:30:00Z"), dailyTotal: 30)
        windows.accumulate(usage(70), timestamp: iso("2026-01-15T05:30:00Z"), dailyTotal: 70)

        let dailyTotals = windows.snapshot().dailyTotals
        let jan15UTCBucket = iso("2026-01-15T00:00:00Z")

        XCTAssertEqual(dailyTotals.count, 1)
        XCTAssertEqual(dailyTotals[jan15UTCBucket], 100)
    }
}
