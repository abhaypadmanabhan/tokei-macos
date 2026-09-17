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
        let baselineDailyUsage: [Date: TokenUsage]
        let baselineDailyTotals: [Date: Int]
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

    /// Epoch baselines are immutable raw parser snapshots. Their non-overlapping deltas
    /// conserve provider totals across repeated switches, regrouping, and day rollover.
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
            baselineDailyUsage: aggregate?.dailyUsage ?? [:],
            baselineDailyTotals: aggregate?.dailyTotals ?? [:],
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

    private static func epochAllocations(for attribution: RootAttribution) -> [EpochAllocation] {
        var result = Array(repeating: EpochAllocation(), count: attribution.epochs.count)
        for (day, total) in attribution.rawDailyUsage {
            let baselines = attribution.epochs.map { $0.baselineDailyUsage[day] }
            let components = tokenAllocations(total: total, baselines: baselines)
            for index in attribution.epochs.indices {
                result[index].dailyUsage[day] = components[index]
            }
        }
        for (day, total) in attribution.rawDailyTotals {
            let allocated = allocate(
                total: total,
                baselines: attribution.epochs.map { $0.baselineDailyTotals[day] }
            )
            for index in attribution.epochs.indices {
                result[index].dailyTotals[day] = allocated[index] ?? 0
            }
        }
        return result
    }

    private static func tokenAllocations(
        total: TokenUsage,
        baselines: [TokenUsage?]
    ) -> [TokenUsage] {
        let input = allocate(total: total.inputTokens, baselines: baselines.map { $0?.inputTokens })
        let output = allocate(total: total.outputTokens, baselines: baselines.map { $0?.outputTokens })
        let cacheRead = allocate(
            total: total.cacheReadTokens,
            baselines: baselines.map { $0?.cacheReadTokens }
        )
        let cacheCreation = allocate(
            total: total.cacheCreationTokens,
            baselines: baselines.map { $0?.cacheCreationTokens }
        )
        let reasoning = allocate(
            total: total.reasoningTokens,
            baselines: baselines.map { $0?.reasoningTokens }
        )
        return baselines.indices.map { index in
            TokenUsage(
                inputTokens: input[index],
                outputTokens: output[index],
                cacheReadTokens: cacheRead[index],
                cacheCreationTokens: cacheCreation[index],
                reasoningTokens: reasoning[index],
                confidence: total.confidence
            )
        }
    }

    /// Turn raw cumulative values at identity boundaries into non-overlapping deltas.
    /// The clamp keeps current raw data authoritative after truncation or replacement.
    private static func allocate(total: Int?, baselines: [Int?]) -> [Int?] {
        guard let total else { return Array(repeating: nil, count: baselines.count) }
        let boundedTotal = max(0, total)
        var floor = 0
        let starts = baselines.map { baseline -> Int in
            let start = min(boundedTotal, max(floor, max(0, baseline ?? 0)))
            floor = start
            return start
        }
        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : boundedTotal
            return end - starts[index]
        }
    }
}
