import XCTest
@testable import AIUsageDashboardCore

/// The burn surfaces' model (WP-C): it follows `DashboardViewModel.burn`, queues one
/// celebration per evaluation that brings moments, and never replays one.
@MainActor
final class BurnBoardTests: XCTestCase {
    /// Friday 2026-11-13 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_571_200)

    private func snapshot(moments: [BurnMoment], streak: Int = 11) -> BurnSnapshot {
        let sample = BurnSnapshot.sample(now: now)
        return BurnSnapshot(
            generatedAt: now, today: sample.today,
            streak: BurnStreak(current: streak, longest: max(streak, 11), todayHit: true),
            expiring: sample.expiring, records: sample.records, leaderboard: sample.leaderboard,
            badges: sample.badges, recentWindows: sample.recentWindows, tier: sample.tier,
            monthValueMultiple: sample.monthValueMultiple, moments: moments
        )
    }

    func testFollowsTheViewModelsBurn() {
        let viewModel = DashboardViewModel()
        let board = BurnBoard(viewModel: viewModel)
        XCTAssertEqual(board.snapshot, viewModel.burn)
        let next = snapshot(moments: [])
        viewModel.burn = next
        XCTAssertEqual(board.snapshot, next)
        XCTAssertNil(board.celebration, "an evaluation without moments celebrates nothing")
    }

    func testCelebratesTheHeadlineMomentOnce() {
        let board = BurnBoard(snapshot: .empty(now: now), now: { self.now })
        let withMoments = snapshot(moments: [.record(.bestDay), .badge(.streak7)])
        board.apply(withMoments)
        let first = board.celebration
        XCTAssertEqual(first?.moment, .badge(.streak7), "a badge outranks a record")

        board.apply(withMoments)
        XCTAssertEqual(board.celebration?.id, first?.id, "a re-published snapshot does not queue it again")

        board.finish(UUID())
        XCTAssertEqual(board.celebration?.id, first?.id, "finishing another celebration leaves this one")
        board.finish(first!.id)
        XCTAssertNil(board.celebration)

        board.apply(snapshot(moments: [], streak: 12))
        XCTAssertNil(board.celebration, "the next evaluation has no moments, so nothing replays")
    }

    /// Review r1 S1: Burn stays mounted under an opaque agent drill-in. A covered surface gets
    /// no celebration, so nothing plays or calls `finish` there, and the moment waits.
    func testACoveredSurfaceLeavesTheCelebrationPending() {
        let board = BurnBoard(snapshot: .empty(now: now), now: { self.now })
        board.apply(snapshot(moments: [.tierUp(.maxxing)]))
        let pending = board.celebration
        XCTAssertNotNil(pending)
        XCTAssertNil(board.celebration(forSurfaceExposed: false), "a covered Burn pane must not get it")
        XCTAssertEqual(board.celebration?.id, pending?.id, "still pending after the covered pass")
        XCTAssertEqual(board.celebration(forSurfaceExposed: true)?.id, pending?.id, "the exposed pane plays it")
    }

    func testGoblinModeIsTheBigCelebrationAndStaleOnesExpire() {
        let board = BurnBoard(snapshot: .empty(now: now), now: { self.now })
        board.apply(snapshot(moments: [.badge(.goblinMode), .tierUp(.goblinMode)]))
        XCTAssertEqual(board.celebration?.isGoblinMode, true)
        XCTAssertNil(board.celebration?.badge, "the tier up plays on the ring, not a badge cell")
        XCTAssertEqual(board.celebration?.isStale(at: now.addingTimeInterval(11 * 3_600)), false)
        XCTAssertEqual(board.celebration?.isStale(at: now.addingTimeInterval(13 * 3_600)), true)
    }
}
