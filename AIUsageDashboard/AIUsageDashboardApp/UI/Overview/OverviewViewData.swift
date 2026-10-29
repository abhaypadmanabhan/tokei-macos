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
        guard let key = ProviderMetadata.liveQuotaEnabledKey(for: id) else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    func quotaState(for id: ProviderID) -> ProviderQuotaState {
        if let util = tightestByProvider[id] { return .live(util) }
        if ProviderMetadata.showsPendingQuota(for: id) {
            return liveQuotaEnabled(id) ? .fetching : .connect
        }
        return .localOnly
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

    /// Every visible provider as a quota bar row for the Quota-metric main view —
    /// live windows first (fullest-first), then the honest non-live states so nothing
    /// the user enabled is dropped (FIX 3). Sorted so the pressure that bites is on top.
    var quotaRows: [AgentQuotaRow] {
        visibleProviders
            .map { id -> AgentQuotaRow in
                let state = quotaState(for: id)
                var pace: QuotaPace?
                if case .live(let util) = state { pace = viewModel.pace(for: util) }
                return AgentQuotaRow(id: id, name: displayName(id), state: state, pace: pace)
            }
            .sorted { lhs, rhs in
                if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                return lhs.usedPercent > rhs.usedPercent
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

    // MARK: Hero copy

    /// The hero's headline figure for the active lens. "—" when the lens has nothing
    /// honest to show — never a 0 standing in for absent data.
    var heroNumber: String {
        switch metric {
        case .usage: return mergedToday.totalTokens.map { TokenFormatter.format($0) } ?? "—"
        case .quota:
            guard let reading = viewModel.tightestAccountPressure else { return "—" }
            return "\(Int(round(reading.usedPercent)))%"
        }
    }

    var heroNumericValue: Double? {
        switch metric {
        case .usage: return mergedToday.totalTokens.map(Double.init)
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
