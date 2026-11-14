import Observation
import XCTest
@testable import AIUsageDashboardCore

/// WP-C AC 6: the status-item label redraws only when what it shows changes. Each label render
/// makes `NSStatusItem` redraw its replicant snapshot, which a Time Profiler pass found to be the
/// largest block inside tab-switch stalls when the label observed the whole view model.
@MainActor
final class MenuBarLabelModelTests: XCTestCase {
    private func settle() {
        let turn = expectation(description: "main queue turn")
        DispatchQueue.main.async { turn.fulfill() }
        wait(for: [turn], timeout: 2)
    }

    /// True once any label value the view reads is written.
    private func observe(_ model: MenuBarLabelModel) -> () -> Bool {
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        withObservationTracking {
            _ = model.todayTotal
            _ = model.todayIsUnknown
            _ = model.tightestPercent
            _ = model.lifetimeTokens
            _ = model.isLoading
        } onChange: {
            flag.fired = true
        }
        return { flag.fired }
    }

    func testAWriteTheLabelDoesNotShowLeavesItAlone() {
        let viewModel = DashboardViewModel()
        let model = MenuBarLabelModel(viewModel: viewModel)
        let fired = observe(model)
        viewModel.showingSettings = true   // what every tab switch used to send
        viewModel.showingSettings = false
        viewModel.range = .thirtyDay
        settle()
        XCTAssertFalse(fired(), "a write that changes nothing on the label must not redraw the status item")
    }

    func testTodaysTokensReachTheLabel() {
        for id in ProviderID.allCases { ProviderVisibility.setHidden(false, for: id) }
        let viewModel = DashboardViewModel()
        let model = MenuBarLabelModel(viewModel: viewModel)
        let fired = observe(model)
        viewModel.snapshots = [ProviderSnapshot(
            providerID: .claudeCode, displayName: "Claude Code", authStatus: .authenticated,
            todayUsage: TokenUsage(inputTokens: 1_200_000, outputTokens: 300_000, confidence: .exact),
            weekUsage: .unavailable
        )]
        settle()
        XCTAssertTrue(fired())
        XCTAssertEqual(model.todayTotal, 1_500_000)
    }

    func testLoadingFlagDrivesTheSpinner() {
        let viewModel = DashboardViewModel()
        let model = MenuBarLabelModel(viewModel: viewModel)
        viewModel.isLoading = true
        settle()
        XCTAssertTrue(model.isLoading)
        viewModel.isLoading = false
        settle()
        XCTAssertFalse(model.isLoading)
    }
}
