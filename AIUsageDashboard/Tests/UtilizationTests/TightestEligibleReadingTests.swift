import XCTest
@testable import AIUsageDashboardCore

/// WP-3 AC3: the quota hero, the menu-bar "Tightest quota" and the status item read one
/// definition, the tightest *eligible* reading. Each case below put the wrong number on
/// screen under the old max-of-everything rule.
@MainActor
final class TightestEligibleReadingTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_793_178_000)

    private func model(_ snapshots: [ProviderSnapshot]) -> DashboardViewModel {
        let model = DashboardViewModel(now: { Self.now })
        model.snapshots = snapshots
        return model
    }

    private func window(
        _ id: ProviderID,
        _ type: QuotaWindowType = .weekly,
        used: Double,
        limit: Double = 100,
        confidence: MetricConfidence = .providerReported,
        resetIn: TimeInterval? = 86_400,
        bucketKey: String? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: id, type: type, used: used, limit: limit,
            resetAt: resetIn.map { Self.now.addingTimeInterval($0) },
            confidence: confidence, source: "test", bucketKey: bucketKey
        )
    }

    private func snapshot(_ id: ProviderID, _ name: String, windows: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id, displayName: name, authStatus: .authenticated,
            quotaWindows: windows, todayUsage: .unavailable, weekUsage: .unavailable
        )
    }

    /// A stale cache replay (`.estimated`) at 95% must not outrank a live 40%.
    func testStaleReplayDoesNotHeadline() {
        let viewModel = model([
            snapshot(.claudeCode, "Claude Code", windows: [window(.claudeCode, used: 95, confidence: .estimated)]),
            snapshot(.codex, "Codex", windows: [window(.codex, used: 40)])
        ])
        XCTAssertEqual(viewModel.tightestAccountPressure?.providerID, .codex)
        XCTAssertEqual(viewModel.tightestAccountPressure?.usedPercent, 40)
    }

    /// A saved 90% whose reset already passed describes a window that refilled.
    func testReadingPastItsResetDoesNotHeadline() {
        let viewModel = model([
            snapshot(.claudeCode, "Claude Code", windows: [
                window(.claudeCode, .fiveHour, used: 90, resetIn: -60),
                window(.claudeCode, .weekly, used: 30)
            ])
        ])
        XCTAssertEqual(viewModel.tightestAccountPressure?.usedPercent, 30)
        XCTAssertEqual(viewModel.tightestAccountPressure?.window, .weekly)
    }

    /// Claude extra usage is a dollar balance (§4.3): 49.5 of 50 must never be "tightest".
    func testCreditBalanceNeverHeadlines() {
        let extra = window(.claudeCode, .credits, used: 49.5, limit: 50, resetIn: nil, bucketKey: "claude_extra_usage")
        let viewModel = model([
            snapshot(.claudeCode, "Claude Code", windows: [extra, window(.claudeCode, used: 12)])
        ])
        XCTAssertEqual(viewModel.tightestAccountPressure?.usedPercent, 12)
        XCTAssertEqual(viewModel.tightestAccountPressure?.window, .weekly)
    }

    /// No eligible reading at all reads as none, not as 0%.
    func testOnlyIneligibleReadingsGiveNoHeadline() {
        let viewModel = model([
            snapshot(.cursor, "Cursor", windows: [window(.cursor, .monthly, used: 70, confidence: .estimated)])
        ])
        XCTAssertNil(viewModel.tightestAccountPressure)
        XCTAssertNil(viewModel.tightestAccountPace)
    }

    /// The reading carries what a surface needs to name it.
    func testReadingNamesProviderWindowAndReset() throws {
        let viewModel = model([
            snapshot(.antigravity, "Antigravity", windows: [
                QuotaWindow(
                    providerID: .antigravity, type: .fiveHour, used: 68, limit: 100,
                    resetAt: Self.now.addingTimeInterval(3_600), confidence: .providerReported,
                    source: "test", label: "Claude and GPT Models"
                )
            ])
        ])
        let reading = try XCTUnwrap(viewModel.tightestAccountPressure)
        XCTAssertEqual(reading.providerName, "Antigravity")
        XCTAssertEqual(reading.accountLabel, "Antigravity")
        XCTAssertFalse(reading.namesAccount)
        XCTAssertEqual(reading.windowLabel, "Claude and GPT Models")
        XCTAssertEqual(reading.resetAt, Self.now.addingTimeInterval(3_600))
    }

    /// Per-provider gauges drop credit balances and readings past their reset, so Claude's
    /// extra-usage dollars never stand in for its quota bar.
    func testGaugeReadingsDropCreditsAndPastResets() {
        let extra = window(.claudeCode, .credits, used: 21.52, limit: 50, resetIn: nil, bucketKey: "claude_extra_usage")
        let viewModel = model([
            snapshot(.claudeCode, "Claude Code", windows: [
                extra,
                window(.claudeCode, .fiveHour, used: 90, resetIn: -60),
                window(.claudeCode, .weekly, used: 12)
            ])
        ])
        XCTAssertEqual(viewModel.utilization.count, 3)
        XCTAssertEqual(viewModel.gaugeUtilizations.map(\.window), [.weekly])
    }
}
