import Foundation

/// The one peak/trust/freshness decision used for account headline selection and public
/// routing metadata. It deliberately evaluates the peak before the trust gate.
public struct AccountQuotaDecision: Sendable {
    public let account: ProviderAccountUsage
    public let status: AccountQuotaStatus
    public let usedPercent: Double?
    public let headroomPercent: Double?
    public let bindingWindowIndex: Int?
    public let validUntil: Date?

    public var isEligible: Bool {
        status == .eligible && headroomPercent != nil && bindingWindowIndex != nil
    }

    public static func evaluate(
        _ account: ProviderAccountUsage,
        providerID: ProviderID,
        now: Date,
        policy: RouteTargetPolicy = .agent
    ) -> AccountQuotaDecision {
        guard account.quotaStatus == .eligible else {
            return nonEligible(account)
        }

        let candidates = account.quotaWindows.enumerated().compactMap { index, window -> (Int, Utilization)? in
            guard let percent = UtilizationEngine.usedPercent(from: window) else { return nil }
            return (index, Utilization(
                providerID: providerID,
                window: window.type,
                usedPercent: percent,
                resetAt: window.resetAt,
                confidence: window.confidence,
                observedAt: window.observedAt
            ))
        }
        guard let peak = candidates.max(by: { lhs, rhs in
            if lhs.1.usedPercent == rhs.1.usedPercent { return lhs.0 > rhs.0 }
            return lhs.1.usedPercent < rhs.1.usedPercent
        }) else {
            return unknown(account)
        }

        // Account routing requires complete trusted, fresh coverage. A comfortable peak
        // cannot hide a missing, stale, estimated, or expired applicable window from the same
        // account. Applicability is provider-specific: Codex plans can expose only a weekly
        // limit, so an uncomputable session/credits shell is not proof of missing coverage.
        // An explicit missing weekly Codex window, and every emitted window for providers whose
        // contracts require them, still makes coverage incomplete.
        guard hasCompleteCoverage(
            candidates: candidates,
            windows: account.quotaWindows,
            providerID: providerID,
            now: now,
            policy: policy
        ) else {
            return unknown(
                account,
                usedPercent: peak.1.usedPercent,
                bindingWindowIndex: peak.0
            )
        }

        let expiryCandidates = [now.addingTimeInterval(AgentSnapshot.stalenessThreshold)]
            + candidates.flatMap { _, utilization in
                [
                    utilization.observedAt?.addingTimeInterval(policy.maxRoutableAge),
                    utilization.resetAt
                ].compactMap { $0 }
            }
        return AccountQuotaDecision(
            account: account,
            status: .eligible,
            usedPercent: peak.1.usedPercent,
            headroomPercent: max(0, 100 - peak.1.usedPercent),
            bindingWindowIndex: peak.0,
            validUntil: expiryCandidates.min()
        )
    }

    public static func headline(
        among accounts: [ProviderAccountUsage],
        providerID: ProviderID,
        now: Date,
        policy: RouteTargetPolicy = .agent
    ) -> AccountQuotaDecision? {
        accounts
            .map { evaluate($0, providerID: providerID, now: now, policy: policy) }
            .filter(\.isEligible)
            .sorted { lhs, rhs in
                if lhs.usedPercent == rhs.usedPercent {
                    return stableID(for: lhs.account, providerID: providerID)
                        < stableID(for: rhs.account, providerID: providerID)
                }
                return (lhs.usedPercent ?? .infinity) < (rhs.usedPercent ?? .infinity)
            }
            .first
    }

    public static func stableID(for account: ProviderAccountUsage, providerID: ProviderID) -> String {
        account.accountID ?? ProviderAccountNormalizer.localID(
            providerID: providerID,
            canonicalRoot: URL(fileURLWithPath: account.id, isDirectory: true)
        )
    }

    private static func hasCompleteCoverage(
        candidates: [(Int, Utilization)],
        windows: [QuotaWindow],
        providerID: ProviderID,
        now: Date,
        policy: RouteTargetPolicy
    ) -> Bool {
        let applicableWindowCount = windows.count { window in
            providerID != .codex
                || window.type == .weekly
                || UtilizationEngine.usedPercent(from: window) != nil
        }
        return candidates.count == applicableWindowCount && candidates.allSatisfy { _, utilization in
            utilization.observedAt != nil
                && policy.isRoutable(utilization, now: now)
                && (utilization.resetAt.map { $0 > now } ?? true)
        }
    }

    private static func nonEligible(_ account: ProviderAccountUsage) -> AccountQuotaDecision {
        AccountQuotaDecision(
            account: account,
            status: account.quotaStatus,
            usedPercent: nil,
            headroomPercent: nil,
            bindingWindowIndex: nil,
            validUntil: nil
        )
    }

    private static func unknown(
        _ account: ProviderAccountUsage,
        usedPercent: Double? = nil,
        bindingWindowIndex: Int? = nil
    ) -> AccountQuotaDecision {
        AccountQuotaDecision(
            account: account,
            status: .unknown,
            usedPercent: usedPercent,
            headroomPercent: nil,
            bindingWindowIndex: bindingWindowIndex,
            validUntil: nil
        )
    }
}
