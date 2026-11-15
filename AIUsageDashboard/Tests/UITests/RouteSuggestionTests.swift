import XCTest
@testable import AIUsageDashboardCore

/// "Send work here next" (WP-C AC 1): every state has real words, the row and the chips name
/// the plan `RoutePlan` (and so `get_route`) recommends, and the copy follows §3.
final class RouteSuggestionTests: XCTestCase {
    /// Friday 2026-11-13 15:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_582_000)

    private func snapshot(
        _ id: ProviderID, _ type: QuotaWindowType = .weekly, used: Double, resetIn: TimeInterval = 3 * 86_400,
        observedAgo: TimeInterval = 60, label: String? = nil
    ) -> ProviderSnapshot {
        let duration: TimeInterval = type == .fiveHour ? 5 * 3_600 : 7 * 86_400
        return ProviderSnapshot(
            providerID: id, displayName: id.rawValue, authStatus: .authenticated,
            quotaWindows: [QuotaWindow(
                providerID: id, type: type, used: used, limit: 100, remaining: 100 - used,
                resetAt: now.addingTimeInterval(resetIn), confidence: .providerReported, source: "test",
                label: label, observedAt: now.addingTimeInterval(-observedAgo), windowDuration: duration
            )],
            todayUsage: .unavailable, weekUsage: .unavailable
        )
    }

    private func suggestion(_ snapshots: [ProviderSnapshot]) -> (RouteSuggestion, RoutePlan) {
        let plan = RoutePlan.make(snapshots: snapshots, now: now)
        return (RouteSuggestion.make(plan, snapshots: snapshots, now: now), plan)
    }

    func testARecommendationNamesThePlanItsWindowAndReasonAndTheNextTwo() {
        let (route, plan) = suggestion([
            snapshot(.claudeCode, used: 40),
            snapshot(.codex, .fiveHour, used: 20, resetIn: 41 * 60),
            snapshot(.cursor, .monthly, used: 92, resetIn: 9 * 86_400),
            snapshot(.gemini, .daily, used: 30, resetIn: 14 * 3_600)
        ])
        XCTAssertEqual(route.state, .recommend)
        XCTAssertEqual(route.title, "Codex")
        XCTAssertEqual(route.window, "5-hour")
        XCTAssertEqual(route.detail, plan.recommendation?.reason)
        XCTAssertEqual(route.detail, "Use this plan before unused capacity resets in 41m.")
        XCTAssertEqual(route.others.count, 2, "the next two on demand, not every plan")
        XCTAssertEqual(route.others.map(\.providerID), Array(plan.rows.dropFirst().prefix(2).map(\.providerID)))
        XCTAssertEqual(route.spoken, "Send work here next: Codex, 5-hour window. Use this plan before unused capacity resets in 41m.")
    }

    /// Codex's weekly window is its tightest, but the 5-hour one is about to reset unused,
    /// which is the reason given: the row must name the 5-hour window, not the weekly one.
    func testTheRowNamesTheWindowItsReasonIsAbout() {
        var codex = snapshot(.codex, .fiveHour, used: 20, resetIn: 41 * 60)
        codex = ProviderSnapshot(
            providerID: .codex, displayName: "Codex", authStatus: .authenticated,
            quotaWindows: codex.quotaWindows + snapshot(.codex, .weekly, used: 36).quotaWindows,
            todayUsage: .unavailable, weekUsage: .unavailable
        )
        let snapshots = [snapshot(.claudeCode, used: 40), codex]
        let plan = RoutePlan.make(snapshots: snapshots, now: now)
        XCTAssertEqual(plan.recommendation?.windowType, .weekly, "precondition: the row carries the tightest window")
        let route = RouteSuggestion.make(plan, snapshots: snapshots, now: now)
        XCTAssertEqual(route.window, "5-hour")
        XCTAssertEqual(route.detail, "Use this plan before unused capacity resets in 41m.")
    }

    func testPopoverLinesFitTheirShortForm() {
        let (route, _) = suggestion([
            snapshot(.codex, .fiveHour, used: 20, resetIn: 41 * 60), snapshot(.claudeCode, used: 58, resetIn: 2 * 3_600 + 9 * 60),
            snapshot(.cursor, .monthly, used: 92)
        ])
        XCTAssertEqual(route.others.map(\.shortStatus), ["42% left · 2h 9m", "Avoid · 8% left"])
    }

    /// The tile and drill-in chips read `target`; it is always the plan's recommendation, and
    /// only when the row recommends.
    func testTheChipTargetIsAlwaysThePlansRecommendation() {
        let cases: [[ProviderSnapshot]] = [
            [snapshot(.claudeCode, used: 40), snapshot(.codex, used: 10)],
            [snapshot(.claudeCode, used: 95), snapshot(.codex, used: 10)],
            [snapshot(.claudeCode, used: 95), snapshot(.codex, used: 90)],
            [snapshot(.claudeCode, used: 20)],
            []
        ]
        for snapshots in cases {
            let (route, plan) = suggestion(snapshots)
            if route.state == .recommend {
                XCTAssertEqual(route.target, plan.recommendation?.providerID)
            } else {
                XCTAssertNil(route.target)
            }
        }
    }

    func testAnAvoidedPlanSaysAvoidInItsLine() {
        let (route, _) = suggestion([snapshot(.claudeCode, used: 40), snapshot(.cursor, .monthly, used: 92)])
        XCTAssertEqual(route.state, .recommend)
        XCTAssertEqual(route.others.first?.avoid, true)
        XCTAssertEqual(route.others.first?.status, "Avoid · 8% left · resets in 3d")
    }

    func testNoPlansSaysWhatWouldChangeIt() {
        let (route, _) = suggestion([])
        XCTAssertEqual(route.state, .none)
        XCTAssertEqual(route.title, "No plan to compare yet")
        XCTAssertNil(route.target)
    }

    func testOnePlanHasNothingToChooseBetween() {
        let (route, _) = suggestion([snapshot(.claudeCode, used: 30)])
        XCTAssertEqual(route.state, .onlyOne)
        XCTAssertEqual(route.detail, "With one plan there is nothing to choose between. Claude Code has 70% left.")
    }

    func testStaleReadingsAreNeverRecommended() {
        let (route, _) = suggestion([
            snapshot(.claudeCode, used: 10, observedAgo: 2 * 3_600),
            snapshot(.codex, used: 20, observedAgo: 2 * 3_600)
        ])
        XCTAssertEqual(route.state, .waiting)
        XCTAssertEqual(route.title, "Waiting for fresh readings")
    }

    func testAFreshPlanBesideAStaleOneSaysSo() {
        let (route, _) = suggestion([
            snapshot(.claudeCode, used: 10, observedAgo: 2 * 3_600), snapshot(.codex, used: 20)
        ])
        XCTAssertEqual(route.state, .onlyOne)
        XCTAssertTrue(route.detail.hasSuffix("One other plan has no fresh reading."), route.detail)
    }

    func testEveryPlanNearlyUsedUpNamesTheFirstToResetAndNeverPointsAtCredits() {
        let (route, _) = suggestion([
            snapshot(.claudeCode, .fiveHour, used: 96, resetIn: 2 * 3_600 + 10 * 60),
            snapshot(.codex, used: 91, resetIn: 2 * 86_400)
        ])
        XCTAssertEqual(route.state, .allNearlyUsedUp)
        XCTAssertEqual(route.title, "Every plan is nearly used up")
        XCTAssertEqual(route.detail, "The first to reset is Claude Code, in 2h 10m.")
        XCTAssertNil(route.target)
        for word in ["credit", "overage", "buy", "upgrade", "extra usage"] {
            XCTAssertFalse(route.detail.localizedCaseInsensitiveContains(word), word)
        }
    }

    /// §3: sentence case, no em dash, in every state's words.
    func testCopyHasNoEmDashAndStartsInSentenceCase() {
        let all: [[ProviderSnapshot]] = [
            [], [snapshot(.claudeCode, used: 30)], [snapshot(.claudeCode, used: 10, observedAgo: 7_200)],
            [snapshot(.claudeCode, used: 96), snapshot(.codex, used: 91)],
            [snapshot(.claudeCode, used: 40), snapshot(.codex, used: 10), snapshot(.cursor, used: 92)]
        ]
        for snapshots in all {
            let (route, _) = suggestion(snapshots)
            for text in [RouteSuggestion.heading, route.title, route.detail, route.spoken] + route.others.map(\.status) {
                XCTAssertFalse(text.contains("\u{2014}"), text)
                XCTAssertEqual(text.first.map { String($0) }, text.first.map { String($0).uppercased() }, text)
            }
            XCTAssertNotEqual(RouteSuggestion.heading, RouteSuggestion.heading.uppercased())
        }
    }

    func testDurationsReadCompactly() {
        XCTAssertEqual(RouteSuggestion.duration(41 * 60), "41m")
        XCTAssertEqual(RouteSuggestion.duration(2 * 3_600), "2h")
        XCTAssertEqual(RouteSuggestion.duration(3 * 86_400 + 6 * 3_600), "3d 6h")
        XCTAssertEqual(RouteSuggestion.duration(20), "under a minute")
    }
}
