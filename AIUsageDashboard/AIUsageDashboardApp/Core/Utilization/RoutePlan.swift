import Foundation

/// A clock-injected plan for the next task. Token-priced balances never enter it.
/// All surfaces consume this order; unknown readings are separate from usable rows.
public struct RoutePlan: Sendable, Equatable {
    public enum Disposition: String, Sendable, Equatable { case ready, avoid }

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: String
        public let providerID: ProviderID
        public let providerName: String
        public let accountLabel: String?
        public let windowType: QuotaWindowType
        public let windowLabel: String?
        public let remainingPercent: Double
        public let resetAt: Date?
        public let secondsToReset: TimeInterval?
        public let paceState: QuotaPace.State?
        public let disposition: Disposition
        public let reason: String
        public let validUntil: Date
        public let expiringAt: Date?
    }

    public struct Unknown: Sendable, Equatable, Identifiable {
        public let id: String
        public let providerID: ProviderID
        public let accountLabel: String?
        public let reason: String
    }

    public let generatedAt: Date
    public let rows: [Row]
    public let unknown: [Unknown]
    public var recommendation: Row? { rows.first.flatMap { $0.disposition == .ready ? $0 : nil } }

    public static func make(snapshots: [ProviderSnapshot], now: Date) -> RoutePlan {
        var ranked: [(Row, Priority)] = []
        var unknown: [Unknown] = []
        for snapshot in snapshots {
            let accounts = snapshot.accounts ?? []
            if accounts.isEmpty {
                append(snapshot: snapshot, windows: snapshot.quotaWindows, id: snapshot.providerID.rawValue,
                       label: nil, eligible: true, now: now, ranked: &ranked, unknown: &unknown)
            } else {
                for (index, account) in accounts.enumerated() {
                    let label = accounts.count > 1 ? plainAccountLabel(account.label, index: index) : nil
                    append(snapshot: snapshot, windows: account.quotaWindows,
                           id: "\(snapshot.providerID.rawValue):\(index + 1)", label: label,
                           eligible: AccountQuotaDecision.evaluate(account, providerID: snapshot.providerID, now: now).isEligible,
                           now: now, ranked: &ranked, unknown: &unknown)
                }
            }
        }
        ranked.sort { precedes($0.1, $1.1) }
        return RoutePlan(generatedAt: now, rows: ranked.map(\.0), unknown: unknown.sorted { $0.id < $1.id })
    }

    // Kept shared with RouteTargetPolicy and account headline selection. The old
    // utilization contract has no reported duration, so ranking uses the duration
    // implied by the window type. Rows still report the provider's actual pace.
    struct Priority {
        let avoid: Bool
        let expiringAt: Date?
        let roomRelativeToPace: Double
        let remainingPercent: Double
        let tie: String
    }

    static func priority(providerID: ProviderID, windows: [QuotaWindow], tie: String, now: Date) -> Priority {
        let limits = windows.filter(isPlanWindow)
        let peak = limits.max { (UtilizationEngine.usedPercent(from: $0) ?? 100) < (UtilizationEngine.usedPercent(from: $1) ?? 100) }
        let used = peak.flatMap(UtilizationEngine.usedPercent(from:)) ?? 100
        let projectedPace = peak.flatMap {
            QuotaPace(usedPercent: used, windowType: $0.type, windowDuration: nil, resetAt: $0.resetAt, now: now)
        }
        let snapshot = ProviderSnapshot(providerID: providerID, displayName: providerID.rawValue,
                                        authStatus: .authenticated, quotaWindows: limits,
                                        todayUsage: .unavailable, weekUsage: .unavailable)
        let expiring = ExpiringHeadroomFinder.find(in: [snapshot], now: now).first?.resetAt
        return Priority(avoid: used >= RouteTargetPolicy.agent.avoidThreshold, expiringAt: expiring,
                        roomRelativeToPace: projectedPace.map { -$0.delta } ?? (100 - used),
                        remainingPercent: 100 - used, tie: tie)
    }

    static func precedes(_ lhs: Priority, _ rhs: Priority) -> Bool {
        if lhs.avoid != rhs.avoid { return !lhs.avoid }
        if !lhs.avoid, lhs.expiringAt != rhs.expiringAt {
            return (lhs.expiringAt ?? .distantFuture) < (rhs.expiringAt ?? .distantFuture)
        }
        if lhs.roomRelativeToPace != rhs.roomRelativeToPace { return lhs.roomRelativeToPace > rhs.roomRelativeToPace }
        if lhs.remainingPercent != rhs.remainingPercent { return lhs.remainingPercent > rhs.remainingPercent }
        return lhs.tie < rhs.tie
    }

    static func isPlanWindow(_ window: QuotaWindow) -> Bool {
        [.session, .fiveHour, .daily, .weekly, .monthly].contains(window.type) && !window.isInformationalCredits
    }

    private static func append(
        snapshot: ProviderSnapshot, windows: [QuotaWindow], id: String, label: String?, eligible: Bool,
        now: Date, ranked: inout [(Row, Priority)], unknown: inout [Unknown]
    ) {
        let limits = windows.filter(isPlanWindow).filter {
            snapshot.providerID != .codex || $0.type == .weekly || UtilizationEngine.usedPercent(from: $0) != nil
        }
        // No plan windows means there is no flat-rate plan to recommend, even if the
        // provider reports tokens or a purchasable credit balance.
        guard !limits.isEmpty else { return }
        let trusted = eligible && limits.allSatisfy { window in
            guard let used = window.used ?? window.remaining.map({ (window.limit ?? 0) - $0 }), used.isFinite,
                  let limit = window.limit, limit.isFinite, limit > 0,
                  RouteTargetPolicy.defaultRoutableConfidences.contains(window.confidence) else { return false }
            if let observed = window.observedAt,
               !(-RouteTargetPolicy.maxClockSkew...RouteTargetPolicy.agent.maxRoutableAge).contains(now.timeIntervalSince(observed)) { return false }
            return window.resetAt.map { $0 > now } ?? true
        }
        guard trusted, let peak = limits.enumerated().max(by: { lhs, rhs in
            let left = UtilizationEngine.usedPercent(from: lhs.element) ?? 100
            let right = UtilizationEngine.usedPercent(from: rhs.element) ?? 100
            return left == right ? lhs.offset > rhs.offset : left < right
        })?.element else {
            unknown.append(Unknown(id: id, providerID: snapshot.providerID, accountLabel: label,
                                   reason: "A fresh, confirmed plan reading is unavailable."))
            return
        }
        let order = priority(providerID: snapshot.providerID, windows: limits, tie: tieKey(snapshot.providerID, id), now: now)
        let pace = QuotaPace(window: peak, now: now)
        let expiry = ([now.addingTimeInterval(AgentSnapshot.stalenessThreshold)] + limits.flatMap {
            [$0.observedAt?.addingTimeInterval(RouteTargetPolicy.agent.maxRoutableAge), $0.resetAt].compactMap { $0 }
        }).min() ?? now
        let reason: String
        if order.avoid {
            reason = "Avoid this plan because only \(Int(order.remainingPercent.rounded()))% remains in its tightest window."
        } else if let reset = order.expiringAt {
            reason = "Use this plan before unused capacity resets in \(AgentSnapshot.compactDuration(reset.timeIntervalSince(now)))."
        } else if pace?.state == .behind {
            reason = "This plan has room to spare relative to its pace."
        } else {
            reason = "This plan has \(Int(order.remainingPercent.rounded()))% left in its tightest window."
        }
        ranked.append((Row(id: id, providerID: snapshot.providerID, providerName: providerName(snapshot.providerID),
                           accountLabel: label, windowType: peak.type,
                           windowLabel: peak.label.flatMap { AgentBurnWindow.isPlainLabel($0) ? $0 : nil },
                           remainingPercent: order.remainingPercent, resetAt: peak.resetAt,
                           secondsToReset: peak.resetAt.map { max(0, $0.timeIntervalSince(now)) }, paceState: pace?.state,
                           disposition: order.avoid ? .avoid : .ready, reason: reason,
                           validUntil: expiry, expiringAt: order.expiringAt), order))
    }

    private static func plainAccountLabel(_ value: String, index: Int) -> String {
        AgentBurnWindow.isPlainLabel(value) && !value.contains("/") ? value : "account \(index + 1)"
    }

    static func tieKey(_ provider: ProviderID, _ suffix: String) -> String {
        "\(ProviderID.allCases.firstIndex(of: provider) ?? 99):\(suffix)"
    }

    private static func providerName(_ id: ProviderID) -> String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .cline: return "Cline"
        case .opencode: return "opencode"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        }
    }
}
