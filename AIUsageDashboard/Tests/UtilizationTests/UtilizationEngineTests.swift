import XCTest
@testable import AIUsageDashboardCore

final class UtilizationEngineTests: XCTestCase {
    // MARK: - Fixtures (Swift literals, matching repo convention)

    private func window(
        _ type: QuotaWindowType,
        providerID: ProviderID,
        used: Double?,
        limit: Double?,
        remaining: Double? = nil,
        resetAt: Date? = nil,
        confidence: MetricConfidence = .providerReported
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: providerID,
            type: type,
            used: used,
            limit: limit,
            remaining: remaining,
            resetAt: resetAt,
            confidence: confidence,
            source: "test"
        )
    }

    private func snapshot(
        _ providerID: ProviderID,
        quotaWindows: [QuotaWindow] = [],
        warnings: [ProviderWarning] = []
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: providerID,
            displayName: providerID.rawValue,
            authStatus: .authenticated,
            quotaWindows: quotaWindows,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            warnings: warnings
        )
    }

    // MARK: - Per-window percent mapping

    func testMapsUsedOverLimitToPercent() throws {
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 30, limit: 100)
        ])
        let result = UtilizationEngine.utilizations(from: [snap])
        XCTAssertEqual(result.count, 1)
        let u = try XCTUnwrap(result.first)
        XCTAssertEqual(u.usedPercent, 30, accuracy: 0.0001)
        XCTAssertEqual(u.window, .monthly)
        XCTAssertEqual(u.providerID, .cursor)
    }

    func testComputesPercentWhenLimitIsNotOneHundred() throws {
        // used=25 of limit=50 → 50%. Proves it divides, not just passes `used` through.
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 25, limit: 50)
        ])
        let result = UtilizationEngine.utilizations(from: [snap])
        XCTAssertEqual(try XCTUnwrap(result.first).usedPercent, 50, accuracy: 0.0001)
    }

    func testDerivesPercentFromRemainingWhenUsedAbsent() throws {
        // remaining=40 of limit=100 → used 60%.
        let snap = snapshot(.antigravity, quotaWindows: [
            window(.weekly, providerID: .antigravity, used: nil, limit: 100, remaining: 40)
        ])
        let result = UtilizationEngine.utilizations(from: [snap])
        XCTAssertEqual(try XCTUnwrap(result.first).usedPercent, 60, accuracy: 0.0001)
    }

    func testClampsPercentToHundred() throws {
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 150, limit: 100)
        ])
        let result = UtilizationEngine.utilizations(from: [snap])
        XCTAssertEqual(try XCTUnwrap(result.first).usedPercent, 100, accuracy: 0.0001)
    }

    func testClampsPercentToZero() throws {
        let snap = snapshot(.antigravity, quotaWindows: [
            window(.weekly, providerID: .antigravity, used: nil, limit: 100, remaining: 140)
        ])
        let result = UtilizationEngine.utilizations(from: [snap])
        XCTAssertEqual(try XCTUnwrap(result.first).usedPercent, 0, accuracy: 0.0001)
    }

    // MARK: - Omission (never zero-fill)

    func testOmitsProviderWithNoQuotaWindows() {
        let result = UtilizationEngine.utilizations(from: [snapshot(.claudeCode)])
        XCTAssertTrue(result.isEmpty)
    }

    func testOmitsWindowWithNoLimit() {
        // A raw `used` with no denominator is not a percentage — omit, don't invent.
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 500, limit: nil)
        ])
        XCTAssertTrue(UtilizationEngine.utilizations(from: [snap]).isEmpty)
    }

    func testOmitsWindowWithZeroLimit() {
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 10, limit: 0)
        ])
        XCTAssertTrue(UtilizationEngine.utilizations(from: [snap]).isEmpty)
    }

    func testOmitsWindowWithNeitherUsedNorRemaining() {
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: nil, limit: 100, remaining: nil)
        ])
        XCTAssertTrue(UtilizationEngine.utilizations(from: [snap]).isEmpty)
    }

    // MARK: - Multiple windows

    func testMapsMultipleWindowsForOneProvider() {
        let snap = snapshot(.antigravity, quotaWindows: [
            window(.fiveHour, providerID: .antigravity, used: 20, limit: 100),
            window(.weekly, providerID: .antigravity, used: 70, limit: 100)
        ])
        let result = UtilizationEngine.utilizations(from: [snap])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.window)), [.fiveHour, .weekly])
    }

    // MARK: - Metadata propagation

    func testPropagatesResetAtAndConfidence() {
        let reset = Date(timeIntervalSince1970: 1_000_000)
        let snap = snapshot(.antigravity, quotaWindows: [
            window(.weekly, providerID: .antigravity, used: 50, limit: 100,
                   resetAt: reset, confidence: .exact)
        ])
        let u = UtilizationEngine.utilizations(from: [snap]).first
        XCTAssertEqual(u?.resetAt, reset)
        XCTAssertEqual(u?.confidence, .exact)
    }

    func testExtractsPlanFromInfoWarning() {
        let snap = snapshot(.cursor,
            quotaWindows: [window(.monthly, providerID: .cursor, used: 10, limit: 100)],
            warnings: [ProviderWarning(message: "Plan: Pro · yearly", level: .info)]
        )
        let u = UtilizationEngine.utilizations(from: [snap]).first
        XCTAssertEqual(u?.plan, "Pro · yearly")
    }

    func testNoPlanWhenNoPlanWarning() {
        let snap = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 10, limit: 100)
        ])
        XCTAssertNil(UtilizationEngine.utilizations(from: [snap]).first?.plan)
    }

    // MARK: - Aggregate

    func testAggregateIsNilWhenNoQuotaData() {
        XCTAssertNil(UtilizationEngine.aggregate(from: [snapshot(.claudeCode)]))
    }

    func testAggregateAveragesPerProviderPeakWindows() throws {
        // Antigravity peak = max(20, 80) = 80. Cursor peak = 40. Mean = 60.
        let ag = snapshot(.antigravity, quotaWindows: [
            window(.fiveHour, providerID: .antigravity, used: 20, limit: 100),
            window(.weekly, providerID: .antigravity, used: 80, limit: 100)
        ])
        let cursor = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 40, limit: 100)
        ])
        let agg = try XCTUnwrap(UtilizationEngine.aggregate(from: [ag, cursor]))
        XCTAssertEqual(agg.usedPercent, 60, accuracy: 0.0001)
        XCTAssertEqual(Set(agg.coveredProviders), [.antigravity, .cursor])
        XCTAssertEqual(agg.coverage, .complete)
    }

    func testAggregateFlagsPartialCoverageWhenProviderHasWindowsButNoneComputable() throws {
        // Cursor contributes; Antigravity HAS a window but it's not computable → omitted → partial.
        let cursor = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 40, limit: 100)
        ])
        let agBroken = snapshot(.antigravity, quotaWindows: [
            window(.weekly, providerID: .antigravity, used: nil, limit: nil)
        ])
        let agg = try XCTUnwrap(UtilizationEngine.aggregate(from: [cursor, agBroken]))
        XCTAssertEqual(agg.usedPercent, 40, accuracy: 0.0001)
        XCTAssertEqual(agg.coveredProviders, [.cursor])
        XCTAssertEqual(agg.coverage, .partial)
    }

    func testAggregateStaysCompleteWhenNonQuotaProvidersPresent() {
        // claudeCode has NO windows at all → it's simply not a quota provider,
        // not "missing". Coverage stays complete.
        let cursor = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 40, limit: 100)
        ])
        let agg = UtilizationEngine.aggregate(from: [snapshot(.claudeCode), cursor])
        XCTAssertEqual(agg?.coverage, .complete)
        XCTAssertEqual(agg?.coveredProviders, [.cursor])
    }

    func testAggregateConfidenceIsMostConservative() {
        let ag = snapshot(.antigravity, quotaWindows: [
            window(.weekly, providerID: .antigravity, used: 80, limit: 100, confidence: .exact)
        ])
        let cursor = snapshot(.cursor, quotaWindows: [
            window(.monthly, providerID: .cursor, used: 40, limit: 100, confidence: .estimated)
        ])
        let agg = UtilizationEngine.aggregate(from: [ag, cursor])
        XCTAssertEqual(agg?.confidence, .estimated)
    }
}
