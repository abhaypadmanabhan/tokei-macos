import Foundation
import AIUsageDashboardCore

/// What "Send work here next" says, read off one `RoutePlan` (the same plan `get_route` and
/// `tokei route` give agents), so a person and an agent asking at the same moment get the
/// same answer. Pure: the popover and Overview draw it, and the tile and drill-in chips
/// name `target`, so no surface can point somewhere the row does not.
struct RouteSuggestion: Equatable {
    enum State: Equatable {
        /// A plan to send work to, with at least one other plan to compare it against.
        case recommend
        /// One plan reports live quota: there is nothing to choose between.
        case onlyOne
        /// No plan-backed agent reports live quota.
        case none
        /// Plans exist, but none has a fresh, confirmed reading.
        case waiting
        /// Every plan with a reading is at or past the avoid line.
        case allNearlyUsedUp
    }

    /// One runner-up under the recommendation.
    struct Line: Equatable, Identifiable {
        let id: String
        let providerID: ProviderID
        let name: String
        /// "Weekly · 64% left · resets in 3h", or "Avoid · 12% left · resets in 4d".
        let status: String
        /// The popover's narrower form: "64% left · 3h", "Avoid · 12% left".
        let shortStatus: String
        let avoid: Bool
    }

    let state: State
    /// The plan's name ("Codex", "Claude Code (work)") or the state's title.
    let title: String
    /// The plan's window ("5-hour"), shown beside the name; nil for the other states.
    let window: String?
    /// The plan's reason sentence, or what the state means and what changes it.
    let detail: String
    /// Where work should go next; nil unless `state` is `.recommend`.
    let target: ProviderID?
    /// The next plans in order (at most two).
    let others: [Line]

    /// What VoiceOver reads for the whole row: the heading, the plan and its reason.
    var spoken: String {
        switch state {
        case .recommend:
            let window = window.map { ", \($0) window" } ?? ""
            return "Send work here next: \(title)\(window). \(detail)"
        default:
            return "Send work here next. \(title). \(detail)"
        }
    }

    static let heading = "Send work here next"

    /// - Parameter snapshots: the snapshots the plan was made from. Only read to name the
    ///   window whose reset makes a plan urgent: a row carries its tightest window, while its
    ///   reason can be about a different one that resets soon (Codex: weekly is tighter, the
    ///   5-hour window is the one about to reset unused).
    static func make(_ plan: RoutePlan, snapshots: [ProviderSnapshot] = [], now: Date) -> RouteSuggestion {
        let staleNote = plan.unknown.isEmpty ? "" : " " + staleSentence(plan.unknown.count)
        guard let first = plan.rows.first else {
            if plan.unknown.isEmpty {
                return RouteSuggestion(
                    state: .none, title: "No plan to compare yet", window: nil,
                    detail: "Tokei suggests where to send work once two agents on a plan report live quota.",
                    target: nil, others: []
                )
            }
            return RouteSuggestion(
                state: .waiting, title: "Waiting for fresh readings", window: nil,
                detail: "No plan has a fresh, confirmed reading right now. Tokei suggests one after the next sync.",
                target: nil, others: []
            )
        }
        guard let pick = plan.recommendation else {
            let soonest = plan.rows.compactMap { row in row.resetAt.map { (row, $0) } }.min { $0.1 < $1.1 }
            let detail = soonest.map { row, reset in
                "The first to reset is \(name(row)), in \(duration(reset.timeIntervalSince(now)))."
            } ?? "None of them reports when it resets."
            return RouteSuggestion(
                state: .allNearlyUsedUp, title: "Every plan is nearly used up", window: nil,
                detail: detail + staleNote, target: nil, others: Array(plan.rows.prefix(3).map(line))
            )
        }
        if plan.rows.count == 1 {
            return RouteSuggestion(
                state: .onlyOne, title: "One plan reporting", window: nil,
                detail: "With one plan there is nothing to choose between. \(name(first)) has "
                    + "\(percent(first.remainingPercent)) left.\(staleNote)",
                target: nil, others: []
            )
        }
        return RouteSuggestion(
            state: .recommend, title: name(pick), window: expiringWindowName(pick, in: snapshots) ?? windowName(pick),
            detail: pick.reason + staleNote,
            target: pick.providerID, others: plan.rows.dropFirst().prefix(2).map(line)
        )
    }

    // MARK: Words

    private static func line(_ row: RoutePlan.Row) -> Line {
        var parts = [row.disposition == .avoid ? "Avoid" : windowName(row), "\(percent(row.remainingPercent)) left"]
        if let seconds = row.secondsToReset { parts.append("resets in \(duration(seconds))") }
        var short = [row.disposition == .avoid ? "Avoid · " : "", "\(percent(row.remainingPercent)) left"].joined()
        if row.disposition != .avoid, let seconds = row.secondsToReset { short += " · \(duration(seconds))" }
        return Line(id: row.id, providerID: row.providerID, name: name(row),
                    status: parts.joined(separator: " · "), shortStatus: short, avoid: row.disposition == .avoid)
    }

    static func name(_ row: RoutePlan.Row) -> String {
        row.accountLabel.map { "\(row.providerName) (\($0))" } ?? row.providerName
    }

    /// The name of the window that resets at the row's `expiringAt`, when one does.
    static func expiringWindowName(_ row: RoutePlan.Row, in snapshots: [ProviderSnapshot]) -> String? {
        guard let expiring = row.expiringAt,
              let snapshot = snapshots.first(where: { $0.providerID == row.providerID }) else { return nil }
        let windows = snapshot.quotaWindows + (snapshot.accounts ?? []).flatMap(\.quotaWindows)
        guard let window = windows.first(where: { $0.resetAt == expiring && planWindowTypes.contains($0.type) }) else {
            return nil
        }
        return windowName(type: window.type, label: nil)
    }

    private static let planWindowTypes: Set<QuotaWindowType> = [.session, .fiveHour, .daily, .weekly, .monthly]

    /// The window's own plain label when it has one ("Opus"), else its kind.
    static func windowName(_ row: RoutePlan.Row) -> String {
        windowName(type: row.windowType, label: row.windowLabel)
    }

    static func windowName(type: QuotaWindowType, label: String?) -> String {
        if let label, !label.isEmpty { return label }
        switch type {
        case .session: return "Session"
        case .fiveHour: return "5-hour"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .perModel: return "Model limit"
        case .credits, .lifetime: return "Plan"
        }
    }

    private static func staleSentence(_ count: Int) -> String {
        count == 1 ? "One other plan has no fresh reading." : "\(count) other plans have no fresh reading."
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// "41m", "2h 10m", "3d 6h": the same compact units the popover's reset column uses.
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3_600, minutes = (seconds % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return minutes > 0 ? "\(minutes)m" : "under a minute"
    }
}
