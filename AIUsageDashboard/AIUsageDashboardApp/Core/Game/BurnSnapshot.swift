import Foundation

// Tokei's burn game, contract 2026-11-14 (patch bible tasks/patch-bibles/2026-11-14.md §4).
//
// The game rewards burning the flat-rate plan capacity the user already pays for: hit a
// daily goal, keep a streak, drain windows before they reset, beat personal records.
// It never rewards spending past the plan: `.credits` windows (Claude extra usage, Codex
// credits) and per-token API spend are not burn. Everything is local; there is no server,
// so the "leaderboard" ranks the user's own agents and days.
//
// The engine (`BurnEngine`, WP-A) fills these values; surfaces (WP-C) only render them.

/// Everything the burn surfaces render, computed once per refresh.
public struct BurnSnapshot: Sendable, Equatable {
    public let generatedAt: Date
    public let today: BurnDay
    public let streak: BurnStreak
    /// Plan windows that reset soon with a large unused share, soonest first.
    public let expiring: [ExpiringHeadroom]
    public let records: BurnRecords
    /// This calendar week's burn by agent, largest first: the user's own leaderboard.
    public let leaderboard: [BurnLeaderboardEntry]
    /// Every badge, in `BurnBadge.allCases` order, unlocked or not.
    public let badges: [BurnBadgeProgress]
    /// Plan windows that reset in the last 7 days and how full each one ended.
    public let recentWindows: [BurnWindowOutcome]
    /// Month-to-date value tier and multiple, the same numbers as the Maxxer scorecard.
    public let tier: MaxxerTier?
    public let monthValueMultiple: Double?
    /// Moments first reached in this evaluation (badge unlocked, record broken, tier up).
    /// Drives one-shot celebrations; empty on the next evaluation unless something new happens.
    public let moments: [BurnMoment]

    public init(
        generatedAt: Date,
        today: BurnDay,
        streak: BurnStreak,
        expiring: [ExpiringHeadroom],
        records: BurnRecords,
        leaderboard: [BurnLeaderboardEntry],
        badges: [BurnBadgeProgress],
        recentWindows: [BurnWindowOutcome],
        tier: MaxxerTier?,
        monthValueMultiple: Double?,
        moments: [BurnMoment]
    ) {
        self.generatedAt = generatedAt
        self.today = today
        self.streak = streak
        self.expiring = expiring
        self.records = records
        self.leaderboard = leaderboard
        self.badges = badges
        self.recentWindows = recentWindows
        self.tier = tier
        self.monthValueMultiple = monthValueMultiple
        self.moments = moments
    }

    /// Share of recent windows' capacity left unused at their resets, 0…100; `nil` when
    /// no window reset in the last 7 days.
    public var leftOnTablePercent: Double? {
        guard !recentWindows.isEmpty else { return nil }
        return recentWindows.map(\.unusedPercent).reduce(0, +) / Double(recentWindows.count)
    }
}

public enum BurnUnit: String, Sendable, Equatable {
    /// API-equivalent US dollars: what the same tokens would cost at public API rates.
    case usd
    case tokens
}

/// The daily target. With plan costs set it is break-even pace: the plans' monthly cost
/// divided by the days in this month, in API-equivalent dollars. Without plan costs it is
/// the user's median active-day tokens over the last 30 days ("beat your usual day").
public struct BurnGoal: Sendable, Equatable {
    public let unit: BurnUnit
    public let target: Double

    public init(unit: BurnUnit, target: Double) {
        self.unit = unit
        self.target = target
    }
}

public struct BurnDay: Sendable, Equatable {
    /// Start of the local day.
    public let day: Date
    /// API-equivalent value burned today; `nil` when nothing today could be priced.
    public let valueUSD: Double?
    public let tokens: Int
    public let goal: BurnGoal?
    /// Burned ÷ goal in the goal's unit: 1 is the goal hit, 2 is double. `nil` without a goal.
    public let progress: Double?

    public init(day: Date, valueUSD: Double?, tokens: Int, goal: BurnGoal?, progress: Double?) {
        self.day = day
        self.valueUSD = valueUSD
        self.tokens = tokens
        self.goal = goal
        self.progress = progress
    }

    public var goalHit: Bool { (progress ?? 0) >= 1 }
}

public struct BurnStreak: Sendable, Equatable {
    /// Consecutive days that hit the daily goal, ending today once today is hit, else
    /// ending yesterday.
    public let current: Int
    public let longest: Int
    public let todayHit: Bool

    public init(current: Int, longest: Int, todayHit: Bool) {
        self.current = current
        self.longest = longest
        self.todayHit = todayHit
    }

    /// A streak carried from yesterday that today has not extended yet.
    public var atRisk: Bool { current > 0 && !todayHit }
}

public enum BurnRecordKind: String, Sendable, Equatable, CaseIterable {
    case bestDay
    case bestWeek
    case bestMonthMultiple
    case longestStreak
}

public struct BurnRecord: Sendable, Equatable {
    public let kind: BurnRecordKind
    /// Dollars for day and week when priced (else tokens), the multiple for a month,
    /// days for a streak.
    public let value: Double
    public let unit: BurnUnit?
    public let achievedAt: Date

    public init(kind: BurnRecordKind, value: Double, unit: BurnUnit?, achievedAt: Date) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.achievedAt = achievedAt
    }
}

public struct BurnRecords: Sendable, Equatable {
    public let bestDay: BurnRecord?
    public let bestWeek: BurnRecord?
    public let bestMonthMultiple: BurnRecord?
    public let longestStreak: BurnRecord?

    public init(bestDay: BurnRecord?, bestWeek: BurnRecord?, bestMonthMultiple: BurnRecord?, longestStreak: BurnRecord?) {
        self.bestDay = bestDay
        self.bestWeek = bestWeek
        self.bestMonthMultiple = bestMonthMultiple
        self.longestStreak = longestStreak
    }

    public static let none = BurnRecords(bestDay: nil, bestWeek: nil, bestMonthMultiple: nil, longestStreak: nil)
}

public struct BurnLeaderboardEntry: Sendable, Equatable, Identifiable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let rank: Int
    /// This week's API-equivalent value; `nil` when the agent's tokens cannot be priced.
    public let valueUSD: Double?
    public let tokens: Int

    public init(providerID: ProviderID, rank: Int, valueUSD: Double?, tokens: Int) {
        self.providerID = providerID
        self.rank = rank
        self.valueUSD = valueUSD
        self.tokens = tokens
    }
}

/// How full a plan window was when it reset.
public struct BurnWindowOutcome: Sendable, Equatable, Identifiable {
    public var id: String { "\(providerID.rawValue)|\(accountID ?? "-")|\(bucketKey)|\(Int(resetAt.timeIntervalSince1970))" }
    public let providerID: ProviderID
    public let accountID: String?
    public let windowType: QuotaWindowType
    public let bucketKey: String
    public let resetAt: Date
    /// Used share at the last reading before the reset, 0…100.
    public let finalUsedPercent: Double

    public init(providerID: ProviderID, accountID: String?, windowType: QuotaWindowType,
                bucketKey: String, resetAt: Date, finalUsedPercent: Double) {
        self.providerID = providerID
        self.accountID = accountID
        self.windowType = windowType
        self.bucketKey = bucketKey
        self.resetAt = resetAt
        self.finalUsedPercent = finalUsedPercent
    }

    public var unusedPercent: Double { max(0, 100 - finalUsedPercent) }
}

/// The badge set. Rules are deterministic over local history; the copy here is the copy
/// the app and the website show.
public enum BurnBadge: String, Sendable, Equatable, CaseIterable, Identifiable {
    case firstBurn
    case paidForItself
    case maxxing
    case goblinMode
    case millionDay
    case tenMillionDay
    case ranItDry
    case fullWeek
    case streak3
    case streak7
    case streak30
    case fleet
    case nothingLeft

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstBurn: return "First burn"
        case .paidForItself: return "Paid for itself"
        case .maxxing: return "Maxxing"
        case .goblinMode: return "Goblin mode"
        case .millionDay: return "Million-token day"
        case .tenMillionDay: return "Ten-million day"
        case .ranItDry: return "Ran it dry"
        case .fullWeek: return "Full week"
        case .streak3: return "Three in a row"
        case .streak7: return "Week on fire"
        case .streak30: return "Thirty days"
        case .fleet: return "Fleet"
        case .nothingLeft: return "Nothing left"
        }
    }

    /// One plain sentence: how to earn it.
    public var rule: String {
        switch self {
        case .firstBurn: return "Burn any priced usage on a plan."
        case .paidForItself: return "Get 1× your plans' cost back in a month."
        case .maxxing: return "Get 2× your plans' cost back in a month."
        case .goblinMode: return "Get 5× your plans' cost back in a month."
        case .millionDay: return "Use a million tokens in one day."
        case .tenMillionDay: return "Use ten million tokens in one day."
        case .ranItDry: return "Finish a 5-hour window at 90% or more."
        case .fullWeek: return "Finish a weekly window at 90% or more."
        case .streak3: return "Hit your daily goal three days in a row."
        case .streak7: return "Hit your daily goal seven days in a row."
        case .streak30: return "Hit your daily goal thirty days in a row."
        case .fleet: return "Use three or more agents in one day."
        case .nothingLeft: return "End every window that resets in a week at 80% or more."
        }
    }
}

public struct BurnBadgeProgress: Sendable, Equatable, Identifiable {
    public var id: BurnBadge { badge }
    public let badge: BurnBadge
    public let unlockedAt: Date?
    /// 0…1 toward unlocking when measurable; `nil` when not.
    public let progress: Double?

    public init(badge: BurnBadge, unlockedAt: Date?, progress: Double?) {
        self.badge = badge
        self.unlockedAt = unlockedAt
        self.progress = progress
    }

    public var isUnlocked: Bool { unlockedAt != nil }
}

public enum BurnMoment: Sendable, Equatable {
    case badge(BurnBadge)
    case record(BurnRecordKind)
    case tierUp(MaxxerTier)
}

/// Nudge settings shared by the engine (WP-A) and Settings (WP-C).
public enum BurnNudgePolicy {
    /// UserDefaults key; unset means on.
    public static let enabledKey = "burnNudgesEnabled"
    /// At most this many burn notifications per local day, across every kind.
    public static let maxPerDay = 2
}
