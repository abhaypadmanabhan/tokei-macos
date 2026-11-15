import Foundation

extension RoutePlan {
    var agentRoute: AgentRoute {
        AgentRoute(generatedAt: generatedAt, rows: rows.map {
            AgentRouteRow(id: $0.id, provider: $0.providerID.rawValue, providerName: $0.providerName,
                          accountLabel: $0.accountLabel, windowType: $0.windowType.rawValue,
                          windowLabel: $0.windowLabel, remainingPercent: $0.remainingPercent,
                          resetAt: $0.resetAt, secondsToReset: $0.secondsToReset, paceState: $0.paceState?.rawValue,
                          disposition: $0.disposition.rawValue, reason: $0.reason,
                          validUntil: $0.validUntil, expiringAt: $0.expiringAt)
        }, unknown: unknown.map {
            AgentRouteUnknown(id: $0.id, provider: $0.providerID.rawValue, accountLabel: $0.accountLabel, reason: $0.reason)
        })
    }
}
