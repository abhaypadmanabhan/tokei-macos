import Foundation

/// A plan quota window that resets soon with a large unused share: capacity the user has
/// already paid for and loses at the reset unless they use it. The one "use it or lose it"
/// signal shared by the burn game, its nudges and the agent snapshot (contract 2026-11-14).
///
/// Only flat-rate plan windows qualify. `.credits` windows (Claude extra usage, Codex
/// purchasable credits) are money spent per token, never something to burn.
public struct ExpiringHeadroom: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(providerID.rawValue)|\(accountID ?? "-")|\(bucketKey)|\(Int(resetAt.timeIntervalSince1970))"
    }

    public let providerID: ProviderID
    public let providerName: String
    /// Stable provider-scoped identity when the provider reports quota per account.
    public let accountID: String?
    /// Short account label ("default", "account-2") when the provider has several accounts.
    public let accountLabel: String?
    public let windowType: QuotaWindowType
    /// The provider's own label for the window, when it has one; surfaces otherwise name
    /// the window by its type.
    public let windowLabel: String?
    public let bucketKey: String
    /// Used share of the window, 0…100, at the latest trusted reading.
    public let usedPercent: Double
    public let resetAt: Date
    /// When the reading was taken, when the provider reports it.
    public let observedAt: Date?
    public let confidence: MetricConfidence

    /// Unused share of the window, 0…100: what is lost at the reset.
    public var unusedPercent: Double { max(0, 100 - usedPercent) }

    public func secondsToReset(from now: Date) -> TimeInterval {
        max(0, resetAt.timeIntervalSince(now))
    }

    public init(
        providerID: ProviderID,
        providerName: String,
        accountID: String? = nil,
        accountLabel: String? = nil,
        windowType: QuotaWindowType,
        windowLabel: String? = nil,
        bucketKey: String,
        usedPercent: Double,
        resetAt: Date,
        observedAt: Date? = nil,
        confidence: MetricConfidence
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.windowType = windowType
        self.windowLabel = windowLabel
        self.bucketKey = bucketKey
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.observedAt = observedAt
        self.confidence = confidence
    }
}

/// Finds expiring headroom across provider snapshots. Pure: every input is an argument,
/// including `now`.
public enum ExpiringHeadroomFinder {
    public struct Policy: Sendable, Equatable {
        /// Smallest unused share (0…100) worth flagging.
        public var minimumUnusedPercent: Double
        /// A reading older than this is not headroom: absence of fresh data is not room.
        public var maximumReadingAge: TimeInterval

        public init(minimumUnusedPercent: Double, maximumReadingAge: TimeInterval) {
            self.minimumUnusedPercent = minimumUnusedPercent
            self.maximumReadingAge = maximumReadingAge
        }

        public static let standard = Policy(minimumUnusedPercent: 25, maximumReadingAge: 30 * 60)

        /// How close the reset must be for a window of this type to count as expiring.
        /// `nil` means the type never does: credits are paid spend, per-model and
        /// lifetime windows are not the plan's main pool.
        public func horizon(for type: QuotaWindowType) -> TimeInterval? {
            switch type {
            case .session, .fiveHour: return 90 * 60
            case .daily: return 3 * 3_600
            case .weekly: return 24 * 3_600
            case .monthly: return 3 * 86_400
            case .credits, .perModel, .lifetime: return nil
            }
        }
    }

    /// Windows that reset within their type's horizon with at least the policy's unused
    /// share, soonest reset first. Providers with a per-account breakdown contribute
    /// each eligible account's own windows (the top-level copy is the headline account's
    /// and would double count); others contribute their top-level windows.
    public static func find(
        in snapshots: [ProviderSnapshot],
        now: Date,
        policy: Policy = .standard
    ) -> [ExpiringHeadroom] {
        var seen = Set<String>()
        var found: [ExpiringHeadroom] = []
        for snapshot in snapshots {
            for candidate in candidates(for: snapshot, now: now, policy: policy)
            where seen.insert(candidate.id).inserted {
                found.append(candidate)
            }
        }
        return found.sorted { lhs, rhs in
            if lhs.resetAt != rhs.resetAt { return lhs.resetAt < rhs.resetAt }
            if lhs.unusedPercent != rhs.unusedPercent { return lhs.unusedPercent > rhs.unusedPercent }
            return lhs.id < rhs.id
        }
    }

    private static func candidates(
        for snapshot: ProviderSnapshot,
        now: Date,
        policy: Policy
    ) -> [ExpiringHeadroom] {
        let accountRows = (snapshot.accounts ?? []).filter { !$0.quotaWindows.isEmpty }
        guard !accountRows.isEmpty else {
            return snapshot.quotaWindows.compactMap {
                headroom($0, snapshot: snapshot, account: nil, now: now, policy: policy)
            }
        }
        let labelled = accountRows.count > 1
        return accountRows.filter { $0.quotaStatus == .eligible }.flatMap { account in
            account.quotaWindows.compactMap {
                headroom($0, snapshot: snapshot, account: account, labelled: labelled, now: now, policy: policy)
            }
        }
    }

    private static func headroom(
        _ window: QuotaWindow,
        snapshot: ProviderSnapshot,
        account: ProviderAccountUsage?,
        labelled: Bool = false,
        now: Date,
        policy: Policy
    ) -> ExpiringHeadroom? {
        guard !window.isCodexIndividualLimit,
              let horizon = policy.horizon(for: window.type),
              window.confidence == .providerReported || window.confidence == .exact,
              let used = window.used, used.isFinite,
              let limit = window.limit, limit.isFinite, limit > 0,
              let resetAt = window.resetAt else { return nil }
        let untilReset = resetAt.timeIntervalSince(now)
        guard untilReset > 0, untilReset <= horizon else { return nil }
        if let observedAt = window.observedAt, now.timeIntervalSince(observedAt) > policy.maximumReadingAge {
            return nil
        }
        let usedPercent = min(100, max(0, used / limit * 100))
        guard 100 - usedPercent >= policy.minimumUnusedPercent else { return nil }
        return ExpiringHeadroom(
            providerID: snapshot.providerID,
            providerName: snapshot.displayName,
            accountID: account?.accountID,
            accountLabel: labelled ? account?.label : nil,
            windowType: window.type,
            windowLabel: window.label,
            bucketKey: window.bucketKey ?? window.type.rawValue,
            usedPercent: usedPercent,
            resetAt: resetAt,
            observedAt: window.observedAt,
            confidence: window.confidence
        )
    }
}
