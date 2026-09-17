import Foundation

/// Assigns each Codex root's raw dated totals to the identities observed on that root.
/// Attributed account rows are projections only; later refreshes always start from parser data.
struct CodexIdentityAttribution {
    struct Profile {
        let account: ProviderAccount
        let profile: AccountProfile
        let aggregate: CodexJSONLParser.AggregateUsage
    }

    private struct IdentityEpoch {
        let accountID: String
        let legacyID: String
        let label: String
        let baselineUsage: TokenUsage
        let baselineTotal: Int
        /// Nil for the identity first observed on this root. A later identity must
        /// produce a quota event at or after this refresh boundary.
        let transitionObservedAt: Date?
    }

    private struct RootAttribution {
        var currentAccountID: String
        var rawDailyUsage: [Date: TokenUsage]
        var rawDailyTotals: [Date: Int]
        var epochs: [IdentityEpoch]
    }

    private struct QuotaProjection {
        let windows: [QuotaWindow]
        let status: AccountQuotaStatus
        let detail: String?
    }

    private struct EpochAllocation {
        var dailyUsage: [Date: TokenUsage] = [:]
        var dailyTotals: [Date: Int] = [:]
    }

    private var attributionByRoot: [String: RootAttribution] = [:]

    /// Epoch baselines are calendar-independent cumulative counters captured at the
    /// transition instant. Their non-overlapping deltas conserve provider totals across
    /// repeated switches, regrouping, calendar changes, and day rollover.
    mutating func attribute(
        accounts: [ProviderAccount],
        profiles: [Profile],
        observedAt: Date
    ) -> [ProviderAccountUsage] {
        refreshRoots(from: profiles, observedAt: observedAt)

        var usageByIdentity: [String: [Date: TokenUsage]] = [:]
        var totalsByIdentity: [String: [Date: Int]] = [:]
        var rootsByIdentity: [String: Set<String>] = [:]
        var historicalMetadata: [String: IdentityEpoch] = [:]
        for (root, attribution) in attributionByRoot.sorted(by: { $0.key < $1.key }) {
            let allocations = Self.epochAllocations(for: attribution)
            for (index, epoch) in attribution.epochs.enumerated() {
                historicalMetadata[epoch.accountID] = historicalMetadata[epoch.accountID] ?? epoch
                rootsByIdentity[epoch.accountID, default: []].insert(root)
                Self.merge(
                    allocations[index],
                    into: epoch.accountID,
                    usageByIdentity: &usageByIdentity,
                    totalsByIdentity: &totalsByIdentity
                )
            }
        }

        let currentByIdentity = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let currentIDs = accounts.map(\.id)
        let historicalIDs = historicalMetadata.keys
            .filter { currentByIdentity[$0] == nil }
            .sorted()
        let todayStart = profiles.first?.aggregate.todayStart

        return (currentIDs + historicalIDs).compactMap { accountID in
            guard let metadata = historicalMetadata[accountID] else { return nil }
            let current = currentByIdentity[accountID]
            let dailyUsage = usageByIdentity[accountID] ?? [:]
            let todayUsage = todayStart.flatMap { dailyUsage[$0] }
                ?? UsageWindows.emptyUsage(.localParsed)
            let quota = current == nil ? nil : quotaProjection(
                profiles: profiles.filter { $0.account.id == accountID }
            )

            return ProviderAccountUsage(
                id: current?.legacyID ?? metadata.legacyID,
                accountID: accountID,
                selector: current?.preferredProfile?.selector,
                label: current?.label ?? metadata.label,
                quotaWindows: quota?.windows ?? [],
                todayUsage: todayUsage,
                dailyTotals: totalsByIdentity[accountID] ?? [:],
                configDirectories: Array(rootsByIdentity[accountID] ?? []).sorted(),
                quotaStatus: quota?.status ?? .unknown,
                quotaStatusDetail: quota?.detail
                    ?? "Historical usage from a previous Codex identity."
            )
        }
    }

    private mutating func refreshRoots(from profiles: [Profile], observedAt: Date) {
        let activeRoots = Set(profiles.map { Self.canonicalPath($0.profile.root) })
        attributionByRoot = attributionByRoot.filter { activeRoots.contains($0.key) }

        for collected in profiles {
            let root = Self.canonicalPath(collected.profile.root)
            let aggregate = collected.aggregate
            if var attribution = attributionByRoot[root] {
                if attribution.currentAccountID != collected.account.id {
                    attribution.currentAccountID = collected.account.id
                    attribution.epochs.append(Self.epoch(
                        for: collected.account,
                        aggregate: aggregate,
                        transitionObservedAt: observedAt
                    ))
                }
                attribution.rawDailyUsage = aggregate.dailyUsage
                attribution.rawDailyTotals = aggregate.dailyTotals
                attributionByRoot[root] = attribution
            } else {
                attributionByRoot[root] = RootAttribution(
                    currentAccountID: collected.account.id,
                    rawDailyUsage: aggregate.dailyUsage,
                    rawDailyTotals: aggregate.dailyTotals,
                    epochs: [Self.epoch(
                        for: collected.account,
                        aggregate: nil,
                        transitionObservedAt: nil
                    )]
                )
            }
        }
    }

    private static func epoch(
        for account: ProviderAccount,
        aggregate: CodexJSONLParser.AggregateUsage?,
        transitionObservedAt: Date?
    ) -> IdentityEpoch {
        IdentityEpoch(
            accountID: account.id,
            legacyID: account.legacyID,
            label: account.label,
            baselineUsage: cumulativeUsage(in: aggregate?.dailyUsage ?? [:]),
            baselineTotal: aggregate?.dailyTotals.values.reduce(0, +) ?? 0,
            transitionObservedAt: transitionObservedAt
        )
    }

    private static func merge(
        _ allocation: EpochAllocation,
        into accountID: String,
        usageByIdentity: inout [String: [Date: TokenUsage]],
        totalsByIdentity: inout [String: [Date: Int]]
    ) {
        for (day, usage) in allocation.dailyUsage {
            if let current = usageByIdentity[accountID]?[day] {
                usageByIdentity[accountID]?[day] = current.merging(usage)
            } else {
                usageByIdentity[accountID, default: [:]][day] = usage
            }
        }
        for (day, total) in allocation.dailyTotals {
            totalsByIdentity[accountID, default: [:]][day, default: 0] += total
        }
    }

    private func quotaProjection(profiles: [Profile]) -> QuotaProjection {
        let withWindows = profiles.filter { !$0.aggregate.quotaWindows.isEmpty }
        let attributable = withWindows.filter { collected in
            let root = Self.canonicalPath(collected.profile.root)
            guard let boundary = attributionByRoot[root]?.epochs.last?.transitionObservedAt else {
                return true
            }
            return Self.latestQuotaObservation(in: collected.aggregate.quotaWindows)
                .map { $0 >= boundary } ?? false
        }
        let selectedAttributable = Self.latestQuotaProfile(in: attributable)
        let selectedRaw = Self.latestQuotaProfile(in: withWindows)
        let windows = selectedAttributable?.aggregate.quotaWindows
            ?? selectedRaw?.aggregate.quotaWindows
            ?? []
        let hasReading = windows.contains { UtilizationEngine.usedPercent(from: $0) != nil }

        if selectedAttributable != nil, hasReading {
            return QuotaProjection(windows: windows, status: .eligible, detail: nil)
        }
        if selectedRaw != nil, hasReading {
            return QuotaProjection(
                windows: windows,
                status: .unknown,
                detail: "Awaiting a quota observation at or after the current Codex identity transition."
            )
        }
        return QuotaProjection(windows: windows, status: .noQuotaSource, detail: nil)
    }

    private static func latestQuotaProfile(in profiles: [Profile]) -> Profile? {
        profiles.max { lhs, rhs in
            (latestQuotaObservation(in: lhs.aggregate.quotaWindows) ?? .distantPast)
                < (latestQuotaObservation(in: rhs.aggregate.quotaWindows) ?? .distantPast)
        }
    }

    private static func latestQuotaObservation(in windows: [QuotaWindow]) -> Date? {
        windows.compactMap(\.observedAt).max()
    }

    private static func canonicalPath(_ root: URL) -> String {
        root.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private extension CodexIdentityAttribution {
    private static func epochAllocations(for attribution: RootAttribution) -> [EpochAllocation] {
        var result = Array(repeating: EpochAllocation(), count: attribution.epochs.count)

        let usageDays = attribution.rawDailyUsage.keys.sorted()
        let usage = usageDays.compactMap { attribution.rawDailyUsage[$0] }
        let input = allocateDaily(
            values: usage.map(\.inputTokens),
            baselines: attribution.epochs.map { $0.baselineUsage.inputTokens }
        )
        let output = allocateDaily(
            values: usage.map(\.outputTokens),
            baselines: attribution.epochs.map { $0.baselineUsage.outputTokens }
        )
        let cacheRead = allocateDaily(
            values: usage.map(\.cacheReadTokens),
            baselines: attribution.epochs.map { $0.baselineUsage.cacheReadTokens }
        )
        let cacheCreation = allocateDaily(
            values: usage.map(\.cacheCreationTokens),
            baselines: attribution.epochs.map { $0.baselineUsage.cacheCreationTokens }
        )
        let reasoning = allocateDaily(
            values: usage.map(\.reasoningTokens),
            baselines: attribution.epochs.map { $0.baselineUsage.reasoningTokens }
        )
        for (dayIndex, day) in usageDays.enumerated() {
            let total = usage[dayIndex]
            for index in attribution.epochs.indices {
                result[index].dailyUsage[day] = TokenUsage(
                    inputTokens: input[dayIndex][index],
                    outputTokens: output[dayIndex][index],
                    cacheReadTokens: cacheRead[dayIndex][index],
                    cacheCreationTokens: cacheCreation[dayIndex][index],
                    reasoningTokens: reasoning[dayIndex][index],
                    confidence: total.confidence
                )
            }
        }

        let totalDays = attribution.rawDailyTotals.keys.sorted()
        let allocatedTotals = allocateDaily(
            values: totalDays.map { attribution.rawDailyTotals[$0] },
            baselines: attribution.epochs.map { $0.baselineTotal }
        )
        for (dayIndex, day) in totalDays.enumerated() {
            for index in attribution.epochs.indices {
                result[index].dailyTotals[day] = allocatedTotals[dayIndex][index] ?? 0
            }
        }
        return result
    }

    static func cumulativeUsage(in dailyUsage: [Date: TokenUsage]) -> TokenUsage {
        let usage = Array(dailyUsage.values)
        func total(_ field: (TokenUsage) -> Int?) -> Int? {
            let values = usage.compactMap(field)
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        return TokenUsage(
            inputTokens: total(\.inputTokens),
            outputTokens: total(\.outputTokens),
            cacheReadTokens: total(\.cacheReadTokens),
            cacheCreationTokens: total(\.cacheCreationTokens),
            reasoningTokens: total(\.reasoningTokens),
            confidence: usage.first?.confidence ?? .localParsed
        )
    }

    /// Split calendar-projected days at calendar-independent cumulative epoch boundaries.
    /// The clamp keeps current raw data authoritative after truncation or replacement.
    static func allocateDaily(
        values: [Int?],
        baselines: [Int?]
    ) -> [[Int?]] {
        guard values.contains(where: { $0 != nil }) else {
            return Array(
                repeating: Array(repeating: nil, count: baselines.count),
                count: values.count
            )
        }
        let boundedTotal = values.compactMap { $0 }.reduce(0) { $0 + max(0, $1) }
        var floor = 0
        let starts = baselines.map { baseline -> Int in
            let start = min(boundedTotal, max(floor, max(0, baseline ?? 0)))
            floor = start
            return start
        }

        var cursor = 0
        return values.map { value in
            guard let value else {
                return Array(repeating: nil, count: starts.count)
            }
            let dayStart = cursor
            let dayEnd = dayStart + max(0, value)
            cursor = dayEnd
            return starts.indices.map { index in
                let epochEnd = index + 1 < starts.count ? starts[index + 1] : boundedTotal
                return max(0, min(dayEnd, epochEnd) - max(dayStart, starts[index]))
            }
        }
    }
}
