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
    // MARK: Quota state

    /// A live reading when the provider has one, else what its row can honestly say.
    func quotaState(for id: ProviderID) -> ProviderQuotaState {
        if let util = tightestByProvider[id] { return .live(util) }
        return .gap(QuotaGap.classify(
            id,
            isEnabled: { UserDefaults.standard.bool(forKey: $0) },
            isSyncing: viewModel.isLoading,
            reason: QuotaGap.reason(for: viewModel.snapshot(for: id))
        ))
    }

    /// Tokens per visible provider in the selected range (the same split the ranged total
    /// above the chart adds up).
    var rangedTokens: [ProviderID: Int] {
        Dictionary(viewModel.providerSplit.map { ($0.provider, $0.tokens) }, uniquingKeysWith: +)
    }

    /// Visible providers that used tokens in the range: one tile each, in `ProviderID` order.
    var activeInRange: [ProviderID] {
        let tokens = rangedTokens
        return visibleProviders.filter { (tokens[$0] ?? 0) > 0 }
    }

    /// Visible providers with no tokens in the range. They collapse into one quiet line
    /// (each name still opens its drill-in) instead of a row of 0 and — tiles.
    var quietInRange: [ProviderID] {
        let tokens = rangedTokens
        return visibleProviders.filter { (tokens[$0] ?? 0) == 0 }
    }

    /// One tile per agent that used tokens in the range: the range's tokens, with today's
    /// share of them underneath.
    var agentModels: [AgentCellModel] {
        let headroom = headroomProviderID
        let tokens = rangedTokens
        return activeInRange.map { id in
            let ranged = tokens[id] ?? 0
            let today = viewModel.snapshot(for: id)?.todayUsage
            return AgentCellModel(
                providerID: id, name: displayName(id),
                stat: TokenFormatter.format(ranged), statValue: Double(ranged),
                statColor: PadzyTheme.ink,
                substat: today?.totalTokens.map { "\(TokenFormatter.format($0)) today" },
                substatColor: PadzyTheme.ink4,
                isEstimated: today?.confidence == .estimated,
                hasHeadroom: id == headroom
            )
        }
    }

    /// One tile per agent with tokens in the range, in the Cost lens: the range's API
    /// estimate, a provider-reported all-time figure, or "no price data", never $0.
    func costAgentModels(_ cost: CostSummary) -> [AgentCellModel] {
        activeInRange.map { id in
            let stat: String
            let caption: String?
            switch cost.providers[id] ?? .noPriceData {
            case let .priced(usd, partial):
                stat = MaxxerMath.formatUSD(usd)
                caption = partial ? "some tokens unpriced" : nil
            case let .reportedAllTime(usd):
                stat = MaxxerMath.formatUSD(usd)
                caption = "reported, all time"
            case .noPriceData:
                stat = "—"
                caption = "no price data"
            }
            return AgentCellModel(
                providerID: id, name: displayName(id), stat: stat, statColor: PadzyTheme.ink,
                substat: caption, substatColor: PadzyTheme.ink4, substatIsWords: true,
                isEstimated: false, hasHeadroom: false
            )
        }
    }

    /// Rows for the Quota lens: live gauges first (fullest on top), then providers that
    /// could report quota but have no reading. Providers with no quota source are not rows;
    /// they are named once on `noQuotaSourceProviders`' line.
    var quotaRows: [AgentQuotaRow] {
        visibleProviders
            .map { id -> AgentQuotaRow in
                let state = quotaState(for: id)
                var pace: QuotaPace?
                if case .live(let util) = state { pace = viewModel.pace(for: util) }
                return AgentQuotaRow(id: id, name: displayName(id), state: state, pace: pace)
            }
            .filter { $0.state != .gap(.noSource) }
            .sorted { lhs, rhs in
                if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                return lhs.usedPercent > rhs.usedPercent
            }
    }

    /// Visible providers with no live quota connector (local logs only), in `ProviderID` order.
    var noQuotaSourceProviders: [ProviderID] {
        visibleProviders.filter { quotaState(for: $0) == .gap(.noSource) }
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

    // MARK: Hero copy

    /// The hero's headline figure for the active lens. "—" when the lens has nothing
    /// honest to show — never a 0 standing in for absent data.
    var heroNumber: String {
        switch metric {
        case .usage: return mergedToday.totalTokens.map { TokenFormatter.format($0) } ?? "—"
        case .cost: return viewModel.overviewCost.todayUSD.map { MaxxerMath.formatUSD($0) } ?? "—"
        case .quota:
            guard let reading = viewModel.tightestAccountPressure else { return "—" }
            return "\(Int(round(reading.usedPercent)))%"
        }
    }

    var heroNumericValue: Double? {
        switch metric {
        case .usage: return mergedToday.totalTokens.map(Double.init)
        case .cost: return viewModel.overviewCost.todayUSD
        case .quota: return viewModel.tightestAccountPressure?.usedPercent
        }
    }

    var heroSubtitle: String {
        switch metric {
        case .usage:
            let count = activeAgentCount
            let agents = "\(count) active agent\(count == 1 ? "" : "s")"
            guard viewModel.showingSavedSnapshots else { return "tokens today across \(agents) · incl. cache" }
            // Saved numbers: name the day they describe and say they are being refreshed.
            let now = Date()
            let day = SavedAgeCopy.dayPhrase(savedAt: viewModel.savedSnapshotsDate, now: now)
            let age = SavedAgeCopy.statusLine(
                savedAt: viewModel.savedSnapshotsDate, updating: viewModel.isLoading, now: now
            )
            return "tokens \(day) across \(agents) · incl. cache · \(age.prefix(1).lowercased())\(age.dropFirst())"
        case .cost:
            let cost = viewModel.overviewCost
            guard cost.todayUSD != nil else { return "No per-model token data to price yet." }
            return (["API estimate for today at public rates"]
                + [AnalyticsFormat.excludedPhrase(cost.todayExcludedShare)].compactMap { $0 })
                .joined(separator: " · ")
        case .quota:
            // The same reading the menu bar calls "Tightest quota", named in full.
            guard let reading = viewModel.tightestAccountPressure else {
                return viewModel.gaugeUtilizations.isEmpty
                    ? "No live quota reading yet."
                    : "No current reading: what's saved is estimated or past its reset."
            }
            return "\(QuotaWindowName.owner(of: reading)), \(QuotaWindowName.phrase(of: reading))"
                + " — the tightest live quota."
        }
    }

    // MARK: Derived display state (data sources preserved from the prior pane)

    /// Every non-hidden provider — one agent cell each, in `ProviderID` order.
    var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { !ProviderVisibility.isHidden($0) }
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

    /// Published windows of visible providers only (D13). The quota hero does not use this
    /// as a "tightest" claim — see `DashboardViewModel.tightestAccountPressure`.
    var tightestWindow: Utilization? {
        MaxxerMath.tightestWindow(in: viewModel.gaugeUtilizations.filter {
            visibleProviders.contains($0.providerID)
        })
    }

    /// Each provider reduced to its tightest (highest-used) live window.
    var tightestByProvider: [ProviderID: Utilization] {
        var result: [ProviderID: Utilization] = [:]
        for util in viewModel.gaugeUtilizations {
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
        viewModel.gaugeUtilizations.filter { !ProviderVisibility.isHidden($0.providerID) }
    }
}
