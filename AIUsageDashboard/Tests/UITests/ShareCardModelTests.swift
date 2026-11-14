import XCTest
@testable import AIUsageDashboardCore

/// "Share my week" (WP-C AC 4): the card says the week's value, the month's multiple and tier,
/// the streak and the top agent, and nothing that identifies an account, a person or a project.
final class ShareCardModelTests: XCTestCase {
    /// Friday 2026-11-13 12:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_571_200)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    /// A snapshot whose account-level parts carry identifiers that must never reach the card.
    private func snapshotWithAccounts() -> BurnSnapshot {
        let sample = BurnSnapshot.sample(now: now, calendar: utc)
        let secrets = (email: "abhay.private@example.com", id: "acct-7f3a9", path: "/Users/someone/src/secret-project")
        return BurnSnapshot(
            generatedAt: sample.generatedAt,
            today: sample.today,
            streak: sample.streak,
            expiring: [
                ExpiringHeadroom(providerID: .claudeCode, providerName: "Claude Code \(secrets.path)",
                                 accountID: secrets.id, accountLabel: secrets.email, windowType: .weekly,
                                 windowLabel: "secret-project", bucketKey: secrets.path, usedPercent: 40,
                                 resetAt: now.addingTimeInterval(3_600), observedAt: now, confidence: .providerReported)
            ],
            records: sample.records,
            leaderboard: sample.leaderboard,
            badges: sample.badges,
            recentWindows: [
                BurnWindowOutcome(providerID: .codex, accountID: secrets.id, windowType: .fiveHour,
                                  bucketKey: secrets.path, resetAt: now.addingTimeInterval(-3_600), finalUsedPercent: 70)
            ],
            tier: sample.tier,
            monthValueMultiple: sample.monthValueMultiple,
            moments: []
        )
    }

    func testCardSaysTheWeekInPlainWords() {
        let card = ShareCardModel(snapshot: .sample(now: now, calendar: utc), calendar: utc)
        // Sample leaderboard: 71.2 + 38.5 + 9.1 priced (Gemini unpriced), 68.7M tokens.
        XCTAssertEqual(card.lines(calendar: utc), [
            "$118.80",
            "of API-equivalent usage this week",
            "2.3× my plans' cost this month",
            "Maxxing",
            "11-day streak",
            "Top agent: Claude Code",
            "68.70M tokens",
            "Week of Nov 9",
            "Tracked on my Mac with Tokei"
        ])
        XCTAssertEqual(card.fileName(calendar: utc), "Tokei week of Nov 9.png")
    }

    func testCardFallsBackToTokensWhenNothingIsPriced() {
        let sample = BurnSnapshot.sample(now: now, calendar: utc)
        let unpriced = BurnSnapshot(
            generatedAt: now, today: sample.today, streak: BurnStreak(current: 0, longest: 0, todayHit: false),
            expiring: [], records: .none,
            leaderboard: [BurnLeaderboardEntry(providerID: .gemini, rank: 1, valueUSD: nil, tokens: 1_200_000)],
            badges: sample.badges, recentWindows: [], tier: nil, monthValueMultiple: nil, moments: []
        )
        let card = ShareCardModel(snapshot: unpriced, calendar: utc)
        XCTAssertEqual(card.lines(calendar: utc), [
            "1.20M", "tokens burned this week", "No streak yet", "Top agent: Gemini", "Week of Nov 9",
            "Tracked on my Mac with Tokei"
        ])
    }

    /// The model has no stored field that can carry an account, and none of the account-level
    /// identifiers in the snapshot reach anything the card draws or names the file.
    func testCardHasNoAccountIdentifiers() {
        let card = ShareCardModel(snapshot: snapshotWithAccounts(), calendar: utc)
        let fields = Mirror(reflecting: card).children.compactMap(\.label)
        XCTAssertEqual(Set(fields), ["weekValueUSD", "weekTokens", "monthMultiple", "tier", "streakDays", "topAgent", "weekOf"],
                       "a new field on the card needs a privacy review and this test updated")
        for value in Mirror(reflecting: card).children.map(\.value) {
            XCTAssertFalse(value is String, "the card stores no free text that could hold a label")
        }
        let drawn = (card.lines(calendar: utc) + [card.fileName(calendar: utc)]).joined(separator: "\n")
        for secret in ["abhay.private@example.com", "acct-7f3a9", "/Users/", "secret-project", "@"] {
            XCTAssertFalse(drawn.contains(secret), "card shows \(secret)")
        }
    }
}
