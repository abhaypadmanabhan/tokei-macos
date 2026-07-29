import SwiftUI
import AIUsageDashboardCore

/// `OverviewView`'s derived display state: the pure "view model → display model" layer
/// that turns snapshots and utilizations into agent cells, quota rows, weekday bars,
/// trend callouts and heat cells.
///
/// Split out of `OverviewView.swift` so the view file is the *layout*, and the
/// derivation that feeds it is one cohesive unit next door. Members are internal rather
/// than private only because Swift's `private` is file-scoped — nothing outside
/// `OverviewView` should call them.
extension OverviewView {
    // MARK: Quota state (FIX 2 + FIX 3)

    /// Whether the provider's live-quota flag is on (same UserDefaults key the
    /// Connections/Agents toggle writes). `false` for local-only providers.
    func liveQuotaEnabled(_ id: ProviderID) -> Bool {
        guard let key = ProviderOverviewRow.liveEnabledKey(for: id) else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    func quotaState(for id: ProviderID) -> ProviderQuotaState {
        if let util = tightestByProvider[id] { return .live(util) }
        if ProviderOverviewRow.connectableProviders.contains(id) {
            return liveQuotaEnabled(id) ? .fetching : .connect
        }
        return .localOnly
    }

    /// One resolved cell per visible provider for the agent grid, resolved for the
    /// active lens: Usage shows today's tokens; Quota shows used% + a `% left` substat
    /// (FIX 2), with an honest connect/fetching state for providers with no live window.
    var agentModels: [AgentCellModel] {
        let headroom = headroomProviderID
        return visibleProviders.map { id in
            switch metric {
            case .usage: return usageCell(id, headroom: headroom)
            case .quota: return quotaCell(id, headroom: headroom)
            }
        }
    }

    func usageCell(_ id: ProviderID, headroom: ProviderID?) -> AgentCellModel {
        let today = viewModel.snapshot(for: id)?.todayUsage
        let tightest = tightestByProvider[id]

        let stat: String
        let color: Color
        var estimated = false
        if let today, let total = today.totalTokens {
            stat = TokenFormatter.format(total)
            color = PadzyTheme.ink
            estimated = today.confidence == .estimated
        } else if let tightest {
            stat = "\(Int(round(tightest.usedPercent)))%"
            color = PadzyTheme.ink2
        } else {
            stat = "—"
            color = PadzyTheme.ink5
        }

        return AgentCellModel(
            providerID: id, name: displayName(id),
            stat: stat, statColor: color,
            isEstimated: estimated, hasHeadroom: id == headroom
        )
    }

    func quotaCell(_ id: ProviderID, headroom: ProviderID?) -> AgentCellModel {
        let stat: String
        let statColor: Color
        let substat: String
        let substatColor: Color
        switch quotaState(for: id) {
        case .live(let util):
            let used = Int(round(max(0, min(100, util.usedPercent))))
            stat = "\(used)%"
            statColor = ProviderOverviewRow.thresholdColor(util.usedPercent)
            substat = "\(100 - used)% left"
            substatColor = PadzyTheme.ink5
        case .fetching:
            stat = "—"; statColor = PadzyTheme.ink3
            substat = "FETCHING…"; substatColor = PadzyTheme.ink5
        case .connect:
            stat = "OFF"; statColor = PadzyTheme.ink4
            substat = "ENABLE →"; substatColor = PadzyTheme.accent
        case .localOnly:
            stat = "—"; statColor = PadzyTheme.ink4
            substat = "LOCAL LOGS"; substatColor = PadzyTheme.ink5
        }
        return AgentCellModel(
            providerID: id, name: displayName(id),
            stat: stat, statColor: statColor,
            substat: substat, substatColor: substatColor,
            isEstimated: false, hasHeadroom: id == headroom && quotaState(for: id).isLive
        )
    }

    /// Every visible provider as a quota bar row for the Quota-metric main view —
    /// live windows first (fullest-first), then the honest non-live states so nothing
    /// the user enabled is dropped (FIX 3). Sorted so the pressure that bites is on top.
    var quotaRows: [AgentQuotaRow] {
        visibleProviders
            .map { AgentQuotaRow(id: $0, name: displayName($0), state: quotaState(for: $0)) }
            .sorted { lhs, rhs in
                if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                return lhs.usedPercent > rhs.usedPercent
            }
    }

    /// Average tokens per weekday (Mon→Sun), bucketing the ranged trend by
    /// `Calendar.component(.weekday)`.
    var weekdayBars: [(label: String, value: Int)] {
        let order = [2, 3, 4, 5, 6, 7, 1] // Calendar weekday (1=Sun); Monday-first display.
        let labels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        var sums: [Int: Int] = [:]
        var counts: [Int: Int] = [:]
        let calendar = Calendar.current
        for point in viewModel.overviewTrend {
            let weekday = calendar.component(.weekday, from: point.date)
            sums[weekday, default: 0] += point.tokens
            counts[weekday, default: 0] += 1
        }
        return zip(order, labels).map { weekday, label in
            let count = counts[weekday] ?? 0
            let avg = count > 0 ? (sums[weekday] ?? 0) / count : 0
            return (label, avg)
        }
    }

    /// Per-day top agent for the trend hover callout — the provider that contributed
    /// the most tokens that day, keyed by start-of-day to match the trend points.
    /// Built from the visible providers' daily totals in the UI (no Core change).
    var trendPointDetails: [Date: TrendPointDetail] {
        let calendar = Calendar.current
        var perDay: [Date: [ProviderID: Int]] = [:]
        for id in visibleProviders {
            guard let daily = viewModel.snapshot(for: id)?.dailyTotals else { continue }
            for (date, tokens) in daily where tokens > 0 {
                perDay[calendar.startOfDay(for: date), default: [:]][id, default: 0] += tokens
            }
        }
        return perDay.reduce(into: [:]) { result, entry in
            guard let top = entry.value.max(by: { $0.value < $1.value }) else { return }
            result[entry.key] = TrendPointDetail(topAgent: displayName(top.key), tint: AgentTint.color(top.key))
        }
    }

    /// Per-cell activity for the agent-coloured punch-card: for each weekday×hour
    /// cell, the visible providers' §4 heatmaps are combined into a total plus the
    /// single agent that contributed most that hour (its `AgentTint` colours the
    /// cell) and a hover tooltip. An hour with no activity from any provider is
    /// `.empty`. The same identity colours the donut and agent grid use.
    var heatCells: [[HeatCell]] {
        let entries: [(id: ProviderID, matrix: [[Int?]])] = visibleProviders
            .compactMap { id in viewModel.heatmap(for: id).map { (id, $0) } }
            .filter { $0.matrix.count == 7 }
        guard !entries.isEmpty else { return [] }

        return (0..<7).map { row in
            (0..<24).map { column -> HeatCell in
                var contributions: [(id: ProviderID, tokens: Int)] = []
                for entry in entries {
                    guard entry.matrix[row].indices.contains(column),
                          let value = entry.matrix[row][column], value > 0 else { continue }
                    contributions.append((entry.id, value))
                }
                guard !contributions.isEmpty else { return .empty }

                contributions.sort { $0.tokens > $1.tokens }
                let total = contributions.reduce(0) { $0 + $1.tokens }
                let leader = contributions[0]
                let name = viewModel.snapshot(for: leader.id)?.displayName
                    ?? leader.id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
                let slotLabel = "\(Self.weekdayNames[row]) · \(AnalyticsFormat.hourLabel(column))"
                return HeatCell(
                    total: total,
                    tint: AgentTint.color(leader.id),
                    slotLabel: slotLabel,
                    agentName: name
                )
            }
        }
    }

    static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // MARK: Hero copy

    /// The hero's headline figure for the active lens. "—" when the lens has nothing
    /// honest to show — never a 0 standing in for absent data.
    var heroNumber: String {
        switch metric {
        case .usage: return mergedToday.totalTokens.map { TokenFormatter.format($0) } ?? "—"
        case .quota: return tightestWindow.map { "\(Int(round($0.usedPercent)))%" } ?? "—"
        }
    }

    var heroSubtitle: String {
        switch metric {
        case .usage:
            let count = activeAgentCount
            return "tokens today across \(count) active agent\(count == 1 ? "" : "s")"
        case .quota:
            guard let tightest = tightestWindow else { return "No live quota connected yet." }
            return "\(displayName(tightest.providerID)) is your tightest window right now."
        }
    }

    // MARK: Derived display state (data sources preserved from the prior pane)

    /// Every non-hidden provider — one agent cell each, in `ProviderID` order.
    var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { !ProviderVisibility.isHidden($0) }
    }

    /// The first **visible** provider reporting more than one signed-in account — what the
    /// one-time discovery notice is about. Hidden providers are excluded deliberately: a
    /// provider the user removed from their canvas should not reintroduce itself through a
    /// notice. Only one is ever surfaced; a stack of them is the naggy failure mode.
    var multiAccountProvider: ProviderSnapshot? {
        visibleProviders
            .compactMap { viewModel.snapshot(for: $0) }
            .first { ($0.accounts?.count ?? 0) > 1 }
    }

    func fallbackName(_ id: ProviderID) -> String {
        id.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func displayName(_ id: ProviderID) -> String {
        viewModel.snapshot(for: id)?.displayName ?? fallbackName(id)
    }

    /// Today's per-metric usage merged across the visible + available providers —
    /// the same Core merge the `01 / OVERVIEW` tab pill uses, so hero and pill can
    /// never disagree. (Preserved verbatim from the prior pane.)
    var mergedToday: TokenUsage {
        MaxxerMath.mergedTodayUsage(in: ProviderVisibility.visible(viewModel.snapshots).filter {
            viewModel.isAvailable($0.providerID)
        })
    }

    /// Visible providers that actually report token data today — the hero's "N
    /// active agents" (Antigravity/Gemini with no token data are excluded).
    var activeAgentCount: Int {
        ProviderVisibility.visible(viewModel.snapshots)
            // Same set `mergedToday` sums. Without the availability filter, a provider
            // that is unavailable but still reports today's tokens was counted in
            // "across N active agents" while contributing nothing to the number above it.
            .filter { viewModel.isAvailable($0.providerID) }
            .filter { $0.todayUsage.totalTokens != nil }
            .count
    }

    /// The single tightest live window across providers (the constraint that
    /// actually bites) — the Quota hero and the ambient banner share this.
    var tightestWindow: Utilization? {
        MaxxerMath.tightestWindow(in: viewModel.utilization)
    }

    /// Each provider reduced to its tightest (highest-used) live window.
    var tightestByProvider: [ProviderID: Utilization] {
        var result: [ProviderID: Utilization] = [:]
        for util in viewModel.utilization {
            if let existing = result[util.providerID] {
                if util.usedPercent > existing.usedPercent { result[util.providerID] = util }
            } else {
                result[util.providerID] = util
            }
        }
        return result
    }

    /// The provider that earns the green "route new work here" dot. Delegates to the
    /// ONE canonical rule (`RouteTargetPolicy.human` via `MaxxerMath.routeTarget`) — the
    /// same rule the drill-in chip and the agent snapshot use, so no two surfaces can
    /// nominate different providers. `nil` until at least two providers have a
    /// *trusted* live reading with a real spread between them, so the dot can no
    /// longer land on a stale `local_estimate`.
    var headroomProviderID: ProviderID? {
        MaxxerMath.routeTarget(in: visibleUtilizations, now: Date())?.providerID
    }

    /// Live readings for providers the user hasn't hidden. `RouteTargetPolicy` has no
    /// opinion on visibility, so the filtering happens here.
    var visibleUtilizations: [Utilization] {
        viewModel.utilization.filter { !ProviderVisibility.isHidden($0.providerID) }
    }
}
