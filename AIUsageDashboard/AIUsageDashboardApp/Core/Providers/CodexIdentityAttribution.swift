import Foundation

/// Assigns each Codex session file to the identity active when its first event occurred.
/// A session that straddles a later identity transition remains owned by its starting identity.
struct CodexIdentityAttribution {
    struct Profile {
        let account: ProviderAccount
        let profile: AccountProfile
        let aggregate: CodexJSONLParser.AggregateUsage
    }

    private struct IdentityTransition {
        let accountID: String
        let legacyID: String
        let label: String
        /// Nil for the identity first observed on this root. Files older than the
        /// first observation belong to that initial identity.
        let observedAt: Date?
    }

    private struct RootAttribution {
        var currentAccountID: String
        var transitions: [IdentityTransition]
    }

    private struct QuotaProjection {
        let windows: [QuotaWindow]
        let status: AccountQuotaStatus
        let detail: String?
    }

    private var attributionByRoot: [String: RootAttribution] = [:]

    mutating func attribute(
        accounts: [ProviderAccount],
        profiles: [Profile],
        observedAt: Date
    ) -> [ProviderAccountUsage] {
        refreshRoots(from: profiles, observedAt: observedAt)

        var usageByIdentity: [String: [Date: TokenUsage]] = [:]
        var totalsByIdentity: [String: [Date: Int]] = [:]
        var rootsByIdentity: [String: Set<String>] = [:]
        var historicalMetadata: [String: IdentityTransition] = [:]
        collectUsage(
            profiles: profiles,
            usageByIdentity: &usageByIdentity,
            totalsByIdentity: &totalsByIdentity,
            rootsByIdentity: &rootsByIdentity,
            historicalMetadata: &historicalMetadata
        )

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

    private func collectUsage(
        profiles: [Profile],
        usageByIdentity: inout [String: [Date: TokenUsage]],
        totalsByIdentity: inout [String: [Date: Int]],
        rootsByIdentity: inout [String: Set<String>],
        historicalMetadata: inout [String: IdentityTransition]
    ) {
        for collected in profiles.sorted(by: {
            Self.canonicalPath($0.profile.root) < Self.canonicalPath($1.profile.root)
        }) {
            let root = Self.canonicalPath(collected.profile.root)
            guard let attribution = attributionByRoot[root] else { continue }

            for transition in attribution.transitions {
                historicalMetadata[transition.accountID] =
                    historicalMetadata[transition.accountID] ?? transition
                rootsByIdentity[transition.accountID, default: []].insert(root)
            }
            for file in collected.aggregate.files.sorted(by: { $0.path < $1.path }) {
                let owner = Self.owner(of: file, transitions: attribution.transitions)
                Self.merge(
                    file,
                    into: owner.accountID,
                    usageByIdentity: &usageByIdentity,
                    totalsByIdentity: &totalsByIdentity
                )
            }
        }
    }

    private mutating func refreshRoots(from profiles: [Profile], observedAt: Date) {
        let activeRoots = Set(profiles.map { Self.canonicalPath($0.profile.root) })
        attributionByRoot = attributionByRoot.filter { activeRoots.contains($0.key) }

        for collected in profiles {
            let root = Self.canonicalPath(collected.profile.root)
            if var attribution = attributionByRoot[root] {
                if attribution.currentAccountID != collected.account.id {
                    attribution.currentAccountID = collected.account.id
                    attribution.transitions.append(Self.transition(
                        for: collected.account,
                        observedAt: observedAt
                    ))
                }
                attributionByRoot[root] = attribution
            } else {
                attributionByRoot[root] = RootAttribution(
                    currentAccountID: collected.account.id,
                    transitions: [Self.transition(for: collected.account, observedAt: nil)]
                )
            }
        }
    }

    private static func transition(
        for account: ProviderAccount,
        observedAt: Date?
    ) -> IdentityTransition {
        IdentityTransition(
            accountID: account.id,
            legacyID: account.legacyID,
            label: account.label,
            observedAt: observedAt
        )
    }

    private static func owner(
        of file: CodexJSONLParser.FileUsage,
        transitions: [IdentityTransition]
    ) -> IdentityTransition {
        guard let firstEventAt = file.firstEventAt else { return transitions[0] }
        return transitions.last { transition in
            transition.observedAt.map { $0 <= firstEventAt } ?? true
        } ?? transitions[0]
    }

    private static func merge(
        _ file: CodexJSONLParser.FileUsage,
        into accountID: String,
        usageByIdentity: inout [String: [Date: TokenUsage]],
        totalsByIdentity: inout [String: [Date: Int]]
    ) {
        for (day, usage) in file.dailyUsage {
            if let current = usageByIdentity[accountID]?[day] {
                usageByIdentity[accountID]?[day] = current.merging(usage)
            } else {
                usageByIdentity[accountID, default: [:]][day] = usage
            }
        }
        for (day, total) in file.dailyTotals {
            totalsByIdentity[accountID, default: [:]][day, default: 0] += total
        }
    }

    private func quotaProjection(profiles: [Profile]) -> QuotaProjection {
        let withWindows = profiles.filter { !$0.aggregate.quotaWindows.isEmpty }
        let attributable = withWindows.filter { collected in
            let root = Self.canonicalPath(collected.profile.root)
            guard let boundary = attributionByRoot[root]?.transitions.last?.observedAt else {
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
