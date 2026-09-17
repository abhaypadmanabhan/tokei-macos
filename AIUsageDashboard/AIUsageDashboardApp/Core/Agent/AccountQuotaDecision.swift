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
            return AccountQuotaDecision(
                account: account,
                status: account.quotaStatus,
                usedPercent: nil,
                headroomPercent: nil,
                bindingWindowIndex: nil,
                validUntil: nil
            )
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

        // Account routing requires a positive freshness proof. Provider-level legacy
        // readings may still omit observedAt, but they cannot mint an executable selector.
        guard let observedAt = peak.1.observedAt,
              policy.isRoutable(peak.1, now: now),
              peak.1.resetAt.map({ $0 > now }) ?? true else {
            return unknown(
                account,
                usedPercent: peak.1.usedPercent,
                bindingWindowIndex: peak.0
            )
        }

        let expiryCandidates = [
            now.addingTimeInterval(AgentSnapshot.stalenessThreshold),
            observedAt.addingTimeInterval(policy.maxRoutableAge),
            peak.1.resetAt
        ].compactMap { $0 }
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
