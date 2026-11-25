import Foundation
import AIUsageDashboardCore

/// Words and numbers for the burn surfaces: the menu bar strip, the Burn tab and the share card.
/// Pure Foundation over the contract types (`Core/Game/BurnSnapshot.swift`), so the Core test
/// bundle compiles it (`project.yml`) and the wording is tested with a fixed clock.
enum BurnCopy {
    /// The product name of an agent. Burn surfaces name products only, never an account label,
    /// email or path, so a leaderboard row or a shared card cannot leak who the user is.
    static func agentName(_ id: ProviderID) -> String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .cline: return "Cline"
        case .opencode: return "opencode"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        case .grok: return "Grok"
        }
    }

    // MARK: Countdown

    /// "41 min", "3 h 20 min", "19 h", "2 d 4 h"; "now" at or past the reset. Minutes round up
    /// so "0 min" never shows while time is left.
    static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 6 { return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min" }
        if hours < 48 { return "\(hours) h" }
        let days = hours / 24
        let dayHours = hours % 24
        return dayHours == 0 ? "\(days) d" : "\(days) d \(dayHours) h"
    }

    // MARK: Expiring windows

    /// "Codex 5-hour", "Claude Code account-2 weekly": the window named by its agent, the
    /// account when the agent has several, and the window type.
    static func windowName(_ headroom: ExpiringHeadroom) -> String {
        var parts = [agentName(headroom.providerID)]
        if let account = headroom.accountLabel, !account.isEmpty { parts.append(account) }
        parts.append(windowTypeName(headroom.windowType))
        return parts.joined(separator: " ")
    }

    /// "62% left"
    static func percentLeft(_ headroom: ExpiringHeadroom) -> String {
        "\(Int(headroom.unusedPercent.rounded()))% left"
    }

    /// The one-line form the menu bar strip shows: "Codex 5-hour · 62% left · 41 min".
    static func expiringLine(_ headroom: ExpiringHeadroom, now: Date) -> String {
        "\(windowName(headroom)) · \(percentLeft(headroom)) · \(countdown(headroom.secondsToReset(from: now)))"
    }

    /// Spoken form: "Codex 5-hour window, 62 percent left, resets in 41 min".
    static func expiringSpoken(_ headroom: ExpiringHeadroom, now: Date) -> String {
        "\(windowName(headroom)) window, \(Int(headroom.unusedPercent.rounded())) percent left, "
            + "resets in \(countdown(headroom.secondsToReset(from: now)))"
    }

    static let nothingExpiring = "No window resets soon with much left"

    /// The window type mid-line: "5-hour", "weekly", "session".
    static func windowTypeName(_ type: QuotaWindowType) -> String {
        switch type {
        case .session: return "session"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .fiveHour: return "5-hour"
        case .monthly: return "monthly"
        case .credits: return "credits"
        case .perModel: return "per-model"
        case .lifetime: return "lifetime"
        }
    }

    // MARK: Today and the goal

    /// The ring's centre: "62%" under the goal, "1.5×" from the goal up, "—" without a goal.
    static func progressText(_ progress: Double?) -> String {
        guard let progress, progress.isFinite else { return "—" }
        if progress < 1 { return "\(Int((max(0, progress) * 100).rounded(.down)))%" }
        return MaxxerMath.formatMultiple(progress)
    }

    /// Today's burn in the goal's unit: "$14.62", or "8.07M tokens" when unpriced.
    static func todayAmount(_ day: BurnDay) -> String {
        if day.goal?.unit == .tokens || day.valueUSD == nil {
            return "\(TokenFormatter.format(day.tokens)) tokens"
        }
        return MaxxerMath.formatUSD(day.valueUSD)
    }

    /// Burn counts plan usage only (bible §7), so its dollars can differ from the Cost view's
    /// today and are never labelled as that number.
    static let todayOnPlans = "on your plans today"

    /// "of a $9.68 goal" / "of a 6.20M-token goal"; `nil` without a goal.
    static func goalPhrase(_ goal: BurnGoal?) -> String? {
        guard let goal else { return nil }
        switch goal.unit {
        case .usd: return "of a \(MaxxerMath.formatUSD(goal.target)) goal"
        case .tokens: return "of a \(TokenFormatter.format(Int(goal.target.rounded())))-token goal"
        }
    }

    /// Where the goal comes from, said once under the hero.
    static func goalSource(_ goal: BurnGoal?) -> String {
        switch goal?.unit {
        case .usd?: return "Your goal is break-even pace: your plans' monthly cost spread over this month's days."
        case .tokens?: return "Your goal is your usual day: the median of your active days in the last 30."
        case nil: return "Set plan costs in Settings, or keep using your agents: Tokei sets a goal after your first full day."
        }
    }

    static let noGoalTitle = "No daily goal yet"

    /// The Burn tab's fine print (bible §7 "Burn eligibility", 2026-11-14): burn counts plan
    /// providers only, and says the one thing local logs cannot separate.
    static let eligibilityFinePrint = "Counts usage on your plans only. Pay-per-token keys never count. "
        + "Claude Code's logs can't tell extra usage from plan usage, so its totals may include some."

    // MARK: Streak

    enum StreakState: Equatable {
        case alive
        case atRisk
        case none
    }

    static func streakState(_ streak: BurnStreak) -> StreakState {
        if streak.current == 0 { return .none }
        return streak.atRisk ? .atRisk : .alive
    }

    /// "11-day streak", "No streak yet".
    static func streakTitle(_ streak: BurnStreak) -> String {
        streak.current == 0 ? "No streak yet" : "\(streak.current)-day streak"
    }

    /// The state in words, so it never rests on the flame's colour.
    static func streakDetail(_ streak: BurnStreak) -> String {
        switch streakState(streak) {
        case .alive: return "Goal hit today"
        case .atRisk: return "Keep it alive: hit today's goal"
        case .none: return "Hit today's goal to start one"
        }
    }

    // MARK: Records

    static func recordTitle(_ kind: BurnRecordKind) -> String {
        switch kind {
        case .bestDay: return "Best day"
        case .bestWeek: return "Best week"
        case .bestMonthMultiple: return "Best month"
        case .longestStreak: return "Longest streak"
        }
    }

    /// "$31.40", "41.2M tokens", "2.3×", "11 days"; "—" when there is no record yet.
    static func recordValue(_ record: BurnRecord?) -> String {
        guard let record else { return "—" }
        switch record.kind {
        case .bestDay, .bestWeek:
            return record.unit == .tokens
                ? "\(TokenFormatter.format(Int(record.value.rounded()))) tokens"
                : MaxxerMath.formatUSD(record.value)
        case .bestMonthMultiple:
            return MaxxerMath.formatMultiple(record.value)
        case .longestStreak:
            let days = Int(record.value.rounded())
            return days == 1 ? "1 day" : "\(days) days"
        }
    }

    /// "Nov 8", fixed English month names so the mono column never reflows by locale.
    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard let month = parts.month, let day = parts.day, (1...12).contains(month) else { return "" }
        return "\(months[month - 1]) \(day)"
    }

    // MARK: Moments

    /// The words a celebration shows: "New badge: Week on fire", "New record: best day",
    /// "Tier up: Goblin mode".
    static func momentTitle(_ moment: BurnMoment) -> String {
        switch moment {
        case .badge(let badge): return "New badge: \(badge.title)"
        case .record(let kind): return "New record: \(recordTitle(kind).lowercased())"
        case .tierUp(let tier): return "Tier up: \(tier.displayName)"
        }
    }

    /// The one moment worth a celebration when several land at once: a tier up beats a badge,
    /// a badge beats a record; Goblin mode beats everything.
    static func headlineMoment(_ moments: [BurnMoment]) -> BurnMoment? {
        func rank(_ moment: BurnMoment) -> Int {
            switch moment {
            case .tierUp(.goblinMode): return 0
            case .tierUp: return 1
            case .badge: return 2
            case .record: return 3
            }
        }
        return moments.enumerated().min { lhs, rhs in
            rank(lhs.element) == rank(rhs.element) ? lhs.offset < rhs.offset : rank(lhs.element) < rank(rhs.element)
        }?.element
    }

    // MARK: Left on the table

    /// "24% left on the table"; `nil` when no plan window reset in the last 7 days.
    static func leftOnTableHeadline(_ snapshot: BurnSnapshot) -> String? {
        guard let percent = snapshot.leftOnTablePercent else { return nil }
        return "\(Int(percent.rounded()))% left on the table"
    }

    static func leftOnTableDetail(_ snapshot: BurnSnapshot) -> String {
        let count = snapshot.recentWindows.count
        guard count > 0 else { return "No plan window reset in the last 7 days." }
        return "Unused share of the \(count) plan window\(count == 1 ? "" : "s") that reset in the last 7 days."
    }

    // MARK: Leaderboard

    /// This week's entries that burned something. The engine ranks every visible agent; one
    /// with no tokens and no value is a row of zeros, not a place on the board, and nothing to
    /// share (real data 2026-11-14 01:53: Cursor at 0).
    static func burnedThisWeek(_ leaderboard: [BurnLeaderboardEntry]) -> [BurnLeaderboardEntry] {
        leaderboard.filter { $0.tokens > 0 || ($0.valueUSD ?? 0) > 0 }
    }

    /// "$71.20", or "—" when the agent's tokens have no public rate.
    static func leaderboardValue(_ entry: BurnLeaderboardEntry) -> String {
        MaxxerMath.formatUSD(entry.valueUSD)
    }

    static func leaderboardTokens(_ entry: BurnLeaderboardEntry) -> String {
        "\(TokenFormatter.format(entry.tokens)) tokens"
    }

    // MARK: Badges

    /// The SF Symbol for a badge. The unlocked/locked state is carried by the cell's words and
    /// a lock glyph, never by colour alone.
    static func badgeSymbol(_ badge: BurnBadge) -> String {
        switch badge {
        case .firstBurn: return "flame"
        case .paidForItself: return "dollarsign.circle"
        case .maxxing: return "chart.line.uptrend.xyaxis"
        case .goblinMode: return "crown"
        case .millionDay: return "bolt"
        case .tenMillionDay: return "bolt.circle"
        case .ranItDry: return "drop"
        case .fullWeek: return "calendar"
        case .streak3: return "3.circle"
        case .streak7: return "7.circle"
        case .streak30: return "30.circle"
        case .fleet: return "square.stack.3d.up"
        case .nothingLeft: return "gauge.with.dots.needle.100percent"
        }
    }

    /// "Unlocked Nov 10", or the locked badge's progress: "72% there".
    static func badgeStatus(_ progress: BurnBadgeProgress, calendar: Calendar = .current) -> String {
        if let unlockedAt = progress.unlockedAt { return "Unlocked \(shortDate(unlockedAt, calendar: calendar))" }
        guard let value = progress.progress, value > 0 else { return "Locked" }
        return "\(Int((min(1, value) * 100).rounded(.down)))% there"
    }
}

/// The tier ladder Idle → Goblin mode as five equal steps, so the low tiers do not vanish
/// next to a 5× top. Pure, tested.
enum BurnTierLadder {
    struct Step: Hashable {
        let tier: MaxxerTier
        /// The multiple where the tier starts.
        let from: Double
    }

    /// Same cut points as `MaxxerValueEngine`.
    static let thresholds: [Step] = [
        Step(tier: .idle, from: 0), Step(tier: .warming, from: 0.25), Step(tier: .breakEven, from: 1),
        Step(tier: .maxxing, from: 2), Step(tier: .goblinMode, from: 5)
    ]

    /// 0…1 along the ladder for a value multiple: each tier owns a fifth, linear inside it;
    /// Goblin mode's fifth spans 5× to 10×, clamped there.
    static func position(multiple: Double) -> Double {
        guard multiple.isFinite, multiple > 0 else { return 0 }
        let step = 1.0 / Double(thresholds.count)
        for index in thresholds.indices {
            let from = thresholds[index].from
            let to = index + 1 < thresholds.count ? thresholds[index + 1].from : 10
            if multiple < to || index == thresholds.count - 1 {
                let inside = min(1, max(0, (multiple - from) / (to - from)))
                return min(1, Double(index) * step + inside * step)
            }
        }
        return 1
    }
}

/// How a progress value splits into laps: `completed` full laps under the current one, and the
/// current lap's fraction. 0.62 → (0, 0.62); 1.51 → (1, 0.51); exactly 2 → (1, 1).
struct BurnRingLaps: Equatable {
    let completed: Int
    let current: Double

    init(progress: Double?) {
        guard let progress, progress.isFinite, progress > 0 else {
            completed = 0
            current = 0
            return
        }
        if progress <= 1 {
            completed = 0
            current = progress
            return
        }
        let whole = progress.rounded(.down)
        let fraction = progress - whole
        completed = fraction == 0 ? Int(whole) - 1 : Int(whole)
        current = fraction == 0 ? 1 : fraction
    }
}
