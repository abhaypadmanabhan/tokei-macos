import Foundation

public extension BurnSnapshot {
    /// Nothing burned yet: a fresh install, or every provider hidden.
    static func empty(now: Date, calendar: Calendar = .current) -> BurnSnapshot {
        BurnSnapshot(
            generatedAt: now,
            today: BurnDay(day: calendar.startOfDay(for: now), valueUSD: nil, tokens: 0, goal: nil, progress: nil),
            streak: BurnStreak(current: 0, longest: 0, todayHit: false),
            expiring: [],
            records: .none,
            leaderboard: [],
            badges: BurnBadge.allCases.map { BurnBadgeProgress(badge: $0, unlockedAt: nil, progress: 0) },
            recentWindows: [],
            tier: nil,
            monthValueMultiple: nil,
            moments: []
        )
    }

    /// A busy, believable state for SwiftUI previews and design captures. Not real data.
    static func sample(now: Date, calendar: Calendar = .current) -> BurnSnapshot {
        let today = calendar.startOfDay(for: now)
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today) ?? today }
        let unlocked: [BurnBadge: Date] = [
            .firstBurn: daysAgo(40), .paidForItself: daysAgo(30), .maxxing: daysAgo(9),
            .millionDay: daysAgo(38), .tenMillionDay: daysAgo(6), .ranItDry: daysAgo(12),
            .streak3: daysAgo(10), .streak7: daysAgo(4), .fleet: daysAgo(15)
        ]
        let progress: [BurnBadge: Double] = [.goblinMode: 0.46, .fullWeek: 0.72, .streak30: 0.37, .nothingLeft: 0.5]
        return BurnSnapshot(
            generatedAt: now,
            today: BurnDay(day: today, valueUSD: 14.62, tokens: 8_067_521,
                           goal: BurnGoal(unit: .usd, target: 9.68), progress: 14.62 / 9.68),
            streak: BurnStreak(current: 11, longest: 11, todayHit: true),
            expiring: [
                ExpiringHeadroom(providerID: .codex, providerName: "Codex", windowType: .fiveHour,
                                 bucketKey: "codex_primary", usedPercent: 38,
                                 resetAt: now.addingTimeInterval(41 * 60), observedAt: now.addingTimeInterval(-120),
                                 confidence: .providerReported),
                ExpiringHeadroom(providerID: .claudeCode, providerName: "Claude Code", windowType: .weekly,
                                 bucketKey: "claude_weekly", usedPercent: 61,
                                 resetAt: now.addingTimeInterval(19 * 3_600), observedAt: now.addingTimeInterval(-300),
                                 confidence: .providerReported)
            ],
            records: BurnRecords(
                bestDay: BurnRecord(kind: .bestDay, value: 31.4, unit: .usd, achievedAt: daysAgo(6)),
                bestWeek: BurnRecord(kind: .bestWeek, value: 128.9, unit: .usd, achievedAt: daysAgo(7)),
                bestMonthMultiple: BurnRecord(kind: .bestMonthMultiple, value: 2.3, unit: nil, achievedAt: daysAgo(14)),
                longestStreak: BurnRecord(kind: .longestStreak, value: 11, unit: nil, achievedAt: today)
            ),
            leaderboard: [
                BurnLeaderboardEntry(providerID: .claudeCode, rank: 1, valueUSD: 71.2, tokens: 41_200_000),
                BurnLeaderboardEntry(providerID: .codex, rank: 2, valueUSD: 38.5, tokens: 22_900_000),
                BurnLeaderboardEntry(providerID: .cursor, rank: 3, valueUSD: 9.1, tokens: 3_400_000),
                BurnLeaderboardEntry(providerID: .gemini, rank: 4, valueUSD: nil, tokens: 1_200_000)
            ],
            badges: BurnBadge.allCases.map {
                BurnBadgeProgress(badge: $0, unlockedAt: unlocked[$0], progress: unlocked[$0] == nil ? progress[$0] : 1)
            },
            recentWindows: [
                BurnWindowOutcome(providerID: .claudeCode, accountID: nil, windowType: .fiveHour,
                                  bucketKey: "claude_five_hour", resetAt: now.addingTimeInterval(-3 * 3_600), finalUsedPercent: 94),
                BurnWindowOutcome(providerID: .codex, accountID: nil, windowType: .fiveHour,
                                  bucketKey: "codex_primary", resetAt: now.addingTimeInterval(-6 * 3_600), finalUsedPercent: 52),
                BurnWindowOutcome(providerID: .codex, accountID: nil, windowType: .weekly,
                                  bucketKey: "codex_secondary", resetAt: now.addingTimeInterval(-3 * 86_400), finalUsedPercent: 81)
            ],
            tier: .maxxing,
            monthValueMultiple: 2.3,
            moments: []
        )
    }
}
