import AppKit
import XCTest
@testable import AIUsageDashboardCore

/// The burn surfaces' words (WP-C 2026-11-14). Expected strings are written by hand from the
/// fixed clock below, never produced by the formatter under test.
final class BurnCopyTests: XCTestCase {
    /// Friday 2026-11-13 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_571_200)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func headroom(
        _ provider: ProviderID = .codex, type: QuotaWindowType = .fiveHour, used: Double = 38,
        resetsIn seconds: TimeInterval = 41 * 60, accountLabel: String? = nil
    ) -> ExpiringHeadroom {
        ExpiringHeadroom(providerID: provider, providerName: "OpenAI Codex", accountID: accountLabel.map { "id-\($0)" },
                         accountLabel: accountLabel, windowType: type, bucketKey: "b", usedPercent: used,
                         resetAt: now.addingTimeInterval(seconds), observedAt: now, confidence: .providerReported)
    }

    // MARK: Expiring line

    func testExpiringLineMatchesTheSpecExample() {
        XCTAssertEqual(BurnCopy.expiringLine(headroom(), now: now), "Codex 5-hour · 62% left · 41 min")
    }

    func testExpiringLineNamesTheAccountWhenTheAgentHasSeveral() {
        let line = BurnCopy.expiringLine(
            headroom(.claudeCode, type: .weekly, used: 61, resetsIn: 19 * 3_600, accountLabel: "account-2"), now: now
        )
        XCTAssertEqual(line, "Claude Code account-2 weekly · 39% left · 19 h")
    }

    func testCountdownSteps() {
        XCTAssertEqual(BurnCopy.countdown(0), "now")
        XCTAssertEqual(BurnCopy.countdown(-5), "now")
        XCTAssertEqual(BurnCopy.countdown(20), "1 min", "minutes round up, so time left never reads 0 min")
        XCTAssertEqual(BurnCopy.countdown(41 * 60), "41 min")
        XCTAssertEqual(BurnCopy.countdown(60 * 60), "1 h")
        XCTAssertEqual(BurnCopy.countdown(3 * 3_600 + 20 * 60), "3 h 20 min")
        XCTAssertEqual(BurnCopy.countdown(19 * 3_600), "19 h")
        XCTAssertEqual(BurnCopy.countdown(52 * 3_600), "2 d 4 h")
        XCTAssertEqual(BurnCopy.countdown(72 * 3_600), "3 d")
    }

    // MARK: Ring and goal

    func testProgressTextIsPercentUnderTheGoalAndAMultipleFromIt() {
        XCTAssertEqual(BurnCopy.progressText(nil), "—")
        XCTAssertEqual(BurnCopy.progressText(0), "0%")
        XCTAssertEqual(BurnCopy.progressText(0.629), "62%", "never rounds up to a goal not yet reached")
        XCTAssertEqual(BurnCopy.progressText(0.999), "99%")
        XCTAssertEqual(BurnCopy.progressText(1), "1.0×")
        XCTAssertEqual(BurnCopy.progressText(14.62 / 9.68), "1.5×")
    }

    func testRingLapsShowASecondLapPastTheGoal() {
        XCTAssertEqual(BurnRingLaps(progress: nil), BurnRingLaps(progress: 0))
        let under = BurnRingLaps(progress: 0.62)
        XCTAssertEqual(under.completed, 0)
        XCTAssertEqual(under.current, 0.62, accuracy: 1e-9)
        let over = BurnRingLaps(progress: 1.51)
        XCTAssertEqual(over.completed, 1)
        XCTAssertEqual(over.current, 0.51, accuracy: 1e-9)
        let exactlyTwo = BurnRingLaps(progress: 2)
        XCTAssertEqual(exactlyTwo.completed, 1, "a full second lap, not a third lap at zero")
        XCTAssertEqual(exactlyTwo.current, 1, accuracy: 1e-9)
        let third = BurnRingLaps(progress: 2.4)
        XCTAssertEqual(third.completed, 2)
        XCTAssertEqual(third.current, 0.4, accuracy: 1e-9)
    }

    func testTodayAmountAndGoalPhraseFollowTheGoalUnit() {
        let usd = BurnDay(day: now, valueUSD: 14.62, tokens: 8_067_521, goal: BurnGoal(unit: .usd, target: 9.68), progress: 1.5)
        XCTAssertEqual(BurnCopy.todayAmount(usd), "$14.62")
        XCTAssertEqual(BurnCopy.goalPhrase(usd.goal), "of a $9.68 goal")
        let tokens = BurnDay(day: now, valueUSD: 3, tokens: 4_200_000, goal: BurnGoal(unit: .tokens, target: 6_200_000), progress: 0.68)
        XCTAssertEqual(BurnCopy.todayAmount(tokens), "4.20M tokens", "a token goal shows tokens even when priced")
        XCTAssertEqual(BurnCopy.goalPhrase(tokens.goal), "of a 6.20M-token goal")
        XCTAssertNil(BurnCopy.goalPhrase(nil))
        XCTAssertEqual(BurnCopy.todayOnPlans, "on your plans today", "plan burn, never the Cost view's today")
    }

    // MARK: Streak

    func testStreakStatesReadInWords() {
        let alive = BurnStreak(current: 11, longest: 11, todayHit: true)
        let atRisk = BurnStreak(current: 4, longest: 9, todayHit: false)
        let none = BurnStreak(current: 0, longest: 3, todayHit: false)
        XCTAssertEqual(BurnCopy.streakState(alive), .alive)
        XCTAssertEqual(BurnCopy.streakState(atRisk), .atRisk)
        XCTAssertEqual(BurnCopy.streakState(none), .none)
        XCTAssertEqual(BurnCopy.streakTitle(alive), "11-day streak")
        XCTAssertEqual(BurnCopy.streakDetail(atRisk), "Keep it alive: hit today's goal")
        XCTAssertEqual(BurnCopy.streakTitle(none), "No streak yet")
    }

    // MARK: Records and moments

    func testRecordValues() {
        XCTAssertEqual(BurnCopy.recordValue(nil), "—")
        XCTAssertEqual(BurnCopy.recordValue(BurnRecord(kind: .bestDay, value: 31.4, unit: .usd, achievedAt: now)), "$31.40")
        XCTAssertEqual(BurnCopy.recordValue(BurnRecord(kind: .bestWeek, value: 41_200_000, unit: .tokens, achievedAt: now)),
                       "41.20M tokens")
        XCTAssertEqual(BurnCopy.recordValue(BurnRecord(kind: .bestMonthMultiple, value: 2.3, unit: nil, achievedAt: now)), "2.3×")
        XCTAssertEqual(BurnCopy.recordValue(BurnRecord(kind: .longestStreak, value: 1, unit: nil, achievedAt: now)), "1 day")
        XCTAssertEqual(BurnCopy.shortDate(now, calendar: utc), "Nov 13")
    }

    func testMomentTitlesAndWhichMomentHeadlines() {
        XCTAssertEqual(BurnCopy.momentTitle(.badge(.streak7)), "New badge: Week on fire")
        XCTAssertEqual(BurnCopy.momentTitle(.record(.bestDay)), "New record: best day")
        XCTAssertEqual(BurnCopy.momentTitle(.tierUp(.goblinMode)), "Tier up: Goblin mode")
        XCTAssertNil(BurnCopy.headlineMoment([]))
        XCTAssertEqual(BurnCopy.headlineMoment([.record(.bestDay), .badge(.fleet)]), .badge(.fleet))
        XCTAssertEqual(BurnCopy.headlineMoment([.badge(.fleet), .tierUp(.maxxing), .record(.bestWeek)]), .tierUp(.maxxing))
        XCTAssertEqual(BurnCopy.headlineMoment([.tierUp(.maxxing), .tierUp(.goblinMode)]), .tierUp(.goblinMode))
        XCTAssertEqual(BurnCopy.headlineMoment([.record(.bestWeek), .record(.bestDay)]), .record(.bestWeek),
                       "ties keep the engine's order")
    }

    // MARK: Left on the table, ladder, badges

    func testLeftOnTableUsesTheContractAverage() {
        let sample = BurnSnapshot.sample(now: now, calendar: utc)
        // Sample windows ended 94, 52 and 81 % used: (6 + 48 + 19) / 3 = 24.33.
        XCTAssertEqual(BurnCopy.leftOnTableHeadline(sample), "24% left on the table")
        XCTAssertEqual(BurnCopy.leftOnTableDetail(sample), "Unused share of the 3 plan windows that reset in the last 7 days.")
        XCTAssertNil(BurnCopy.leftOnTableHeadline(.empty(now: now, calendar: utc)))
    }

    func testTierLadderGivesEachTierAnEqualFifth() {
        XCTAssertEqual(BurnTierLadder.position(multiple: 0), 0)
        XCTAssertEqual(BurnTierLadder.position(multiple: .nan), 0)
        XCTAssertEqual(BurnTierLadder.position(multiple: 0.25), 0.2, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.position(multiple: 1), 0.4, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.position(multiple: 1.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.position(multiple: 2), 0.6, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.position(multiple: 5), 0.8, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.position(multiple: 7.5), 0.9, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.position(multiple: 40), 1, accuracy: 1e-9)
        XCTAssertEqual(BurnTierLadder.thresholds.map(\.tier), MaxxerTier.allCases, "one step per tier, in order")
    }

    func testEveryBadgeSymbolExists() {
        for badge in BurnBadge.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: BurnCopy.badgeSymbol(badge), accessibilityDescription: nil),
                            "\(badge): \(BurnCopy.badgeSymbol(badge))")
        }
    }

    /// Bible §7: burn never reads as a reward for paid spend.
    func testFinePrintSaysPlansOnlyAndNeverRewardsPaidSpend() {
        let text = BurnCopy.eligibilityFinePrint
        XCTAssertTrue(text.hasPrefix("Counts usage on your plans only. Pay-per-token keys never count."))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("credits"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("overage"))
    }

    func testAZeroRowIsNotAPlaceOnTheBoard() {
        let board = [
            BurnLeaderboardEntry(providerID: .claudeCode, rank: 1, valueUSD: 663.01, tokens: 1_990_000_000),
            BurnLeaderboardEntry(providerID: .gemini, rank: 2, valueUSD: nil, tokens: 1_200_000),
            BurnLeaderboardEntry(providerID: .cursor, rank: 3, valueUSD: nil, tokens: 0)
        ]
        XCTAssertEqual(BurnCopy.burnedThisWeek(board).map(\.providerID), [.claudeCode, .gemini])
        XCTAssertEqual(BurnCopy.burnedThisWeek([board[2]]), [])
    }

    func testBadgeStatus() {
        XCTAssertEqual(BurnCopy.badgeStatus(BurnBadgeProgress(badge: .fleet, unlockedAt: now, progress: 1), calendar: utc),
                       "Unlocked Nov 13")
        XCTAssertEqual(BurnCopy.badgeStatus(BurnBadgeProgress(badge: .streak30, unlockedAt: nil, progress: 0.37)), "37% there")
        XCTAssertEqual(BurnCopy.badgeStatus(BurnBadgeProgress(badge: .streak30, unlockedAt: nil, progress: nil)), "Locked")
    }
}
