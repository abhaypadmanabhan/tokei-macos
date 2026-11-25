import Foundation

/// One allowance that more than one provider draws on, such as the SuperGrok pool that
/// both Grok (CLI, chat) and Cursor's Super plan spend from.
///
/// Each provider that can read the pool tags its window with the pool's `bucketKey`.
/// `deduplicated(_:)` then keeps exactly one copy, so totals, burn, route, alerts and the
/// agent snapshot count the pool once rather than once per provider. It runs on the
/// merged refresh in `SyncEngine`, the single point every consumer reads from.
public enum SharedQuotaPool {
    public static let superGrokBucketKey = "supergrok_pool"
    public static let superGrokLabel = "SuperGrok pool"

    /// The provider whose row shows each pool when several report it.
    static let owners: [String: ProviderID] = [superGrokBucketKey: .grok]

    static func isShared(_ window: QuotaWindow) -> Bool {
        window.bucketKey.map { owners[$0] != nil } ?? false
    }

    /// Keeps one reading of each shared pool: the owner's when it has a usable one, else
    /// the most recently observed. Every other provider loses that window and gains an
    /// info line naming where the pool is shown. Idempotent; order-preserving.
    public static func deduplicated(_ snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        var keeper: [String: ProviderID] = [:]
        for (key, owner) in owners {
            let holders = snapshots.compactMap { snapshot -> (ProviderID, QuotaWindow)? in
                guard let window = snapshot.quotaWindows.first(where: { $0.bucketKey == key }),
                      UtilizationEngine.usedPercent(from: window) != nil else { return nil }
                return (snapshot.providerID, window)
            }
            guard holders.count > 1 else { continue }
            if holders.contains(where: { $0.0 == owner }) {
                keeper[key] = owner
            } else {
                keeper[key] = holders.max { ($0.1.observedAt ?? .distantPast) < ($1.1.observedAt ?? .distantPast) }?.0
            }
        }
        guard !keeper.isEmpty else { return snapshots }

        return snapshots.map { snapshot in
            let dropped = Set(keeper.compactMap { key, provider in
                provider != snapshot.providerID && snapshot.quotaWindows.contains { $0.bucketKey == key } ? key : nil
            })
            guard !dropped.isEmpty else { return snapshot }
            let names = dropped.sorted().map { key in
                "Quota: \(key == superGrokBucketKey ? superGrokLabel : key), shared with "
                    + "\(displayName(keeper[key])); counted once there."
            }
            return snapshot.replacingQuota(
                windows: snapshot.quotaWindows.filter { window in
                    window.bucketKey.map { !dropped.contains($0) } ?? true
                },
                extraWarnings: names.map { ProviderWarning(message: $0, level: .info) }
            )
        }
    }

    private static func displayName(_ id: ProviderID?) -> String {
        switch id {
        case .grok: return "Grok"
        case .cursor: return "Cursor"
        case let other?: return other.rawValue
        case nil: return "another provider"
        }
    }
}

extension ProviderSnapshot {
    /// A copy with a different set of quota windows and extra warnings; everything else kept.
    func replacingQuota(windows: [QuotaWindow], extraWarnings: [ProviderWarning]) -> ProviderSnapshot {
        let existing = Set(warnings.map(\.message))
        return ProviderSnapshot(
            providerID: providerID, displayName: displayName, authStatus: authStatus,
            quotaWindows: windows, todayUsage: todayUsage, weekUsage: weekUsage,
            monthUsage: monthUsage, lifetimeUsage: lifetimeUsage, costUsage: costUsage,
            warnings: warnings + extraWarnings.filter { !existing.contains($0.message) },
            lastSyncedAt: lastSyncedAt, dailyTotals: dailyTotals, hourlyTotals: hourlyTotals,
            dailyModelUsage: dailyModelUsage,
            accounts: accounts, headlineAccountID: headlineAccountID
        )
    }
}
