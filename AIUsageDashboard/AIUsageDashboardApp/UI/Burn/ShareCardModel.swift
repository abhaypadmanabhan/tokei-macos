import Foundation
import AIUsageDashboardCore

/// What the "Share my week" card says. Built only from aggregate numbers and product names: it
/// has no field that can hold an account label, email, path or project name, and
/// `ShareCardModelTests` fails if one appears. Pure Foundation, compiled into the test bundle.
struct ShareCardModel: Equatable {
    /// This calendar week's plan usage across agents at public API prices (burn counts plan
    /// providers only); `nil` when nothing was priced.
    let weekValueUSD: Double?
    let weekTokens: Int
    let monthMultiple: Double?
    let tier: MaxxerTier?
    let streakDays: Int
    let topAgent: ProviderID?
    /// Start of the week the card covers.
    let weekOf: Date

    init(snapshot: BurnSnapshot, calendar: Calendar = .current) {
        let priced = snapshot.leaderboard.compactMap(\.valueUSD)
        weekValueUSD = priced.isEmpty ? nil : priced.reduce(0, +)
        weekTokens = snapshot.leaderboard.map(\.tokens).reduce(0, +)
        monthMultiple = snapshot.monthValueMultiple
        tier = snapshot.tier
        streakDays = snapshot.streak.current
        topAgent = snapshot.leaderboard.min { $0.rank < $1.rank }?.providerID
        weekOf = calendar.dateInterval(of: .weekOfYear, for: snapshot.generatedAt)?.start
            ?? calendar.startOfDay(for: snapshot.generatedAt)
    }

    /// The big number: "$128.90", or "41.2M" tokens when nothing was priced.
    var headline: String {
        weekValueUSD.map { MaxxerMath.formatUSD($0) } ?? TokenFormatter.format(weekTokens)
    }

    var headlineCaption: String {
        weekValueUSD == nil ? "tokens burned on my plans this week" : "burned on my plans this week, at API prices"
    }

    /// "2.3× my plans' cost this month"; `nil` without plan costs.
    var multipleLine: String? {
        guard let monthMultiple, monthMultiple.isFinite else { return nil }
        return "\(MaxxerMath.formatMultiple(monthMultiple)) my plans' cost this month"
    }

    var tierLine: String? { tier?.displayName }

    var streakLine: String {
        streakDays == 0 ? "No streak yet" : "\(streakDays)-day streak"
    }

    var topAgentLine: String? {
        topAgent.map { "Top agent: \(BurnCopy.agentName($0))" }
    }

    var tokensLine: String { "\(TokenFormatter.format(weekTokens)) tokens" }

    func dateLine(calendar: Calendar = .current) -> String {
        "Week of \(BurnCopy.shortDate(weekOf, calendar: calendar))"
    }

    static let footer = "Tracked on my Mac with Tokei"

    /// Every string the card draws, in order. The privacy test reads this.
    func lines(calendar: Calendar = .current) -> [String] {
        [headline, headlineCaption, multipleLine, tierLine, streakLine, topAgentLine,
         weekValueUSD == nil ? nil : tokensLine, dateLine(calendar: calendar), Self.footer]
            .compactMap { $0 }
    }

    /// "Tokei week of Nov 10.png"
    func fileName(calendar: Calendar = .current) -> String {
        "Tokei week of \(BurnCopy.shortDate(weekOf, calendar: calendar)).png"
    }
}
