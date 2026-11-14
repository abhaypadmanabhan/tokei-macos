import Foundation

extension BurnEngine {
    /// One final reading per exact window instance, including account identity.
    static func windowOutcomes(samples: [QuotaSample], now: Date) -> [BurnWindowOutcome] {
        struct Key: Hashable {
            let provider: ProviderID
            let account: String?
            let type: QuotaWindowType
            let bucket: String
            let reset: Date
        }
        let accountProviders = Set(samples.filter { $0.accountID != nil }.map(\.providerID))
        var last: [Key: QuotaSample] = [:]
        for sample in samples {
            guard ExpiringHeadroomFinder.Policy.standard.horizon(for: sample.windowType) != nil,
                  let reset = sample.resetAt, reset <= now, sample.sampledAt < reset,
                  sample.usedPercent.isFinite,
                  sample.accountID != nil || !accountProviders.contains(sample.providerID) else { continue }
            let key = Key(provider: sample.providerID, account: sample.accountID, type: sample.windowType,
                          bucket: sample.bucketKey, reset: reset)
            if last[key].map({ $0.sampledAt >= sample.sampledAt }) == true { continue }
            last[key] = sample
        }
        return last.map { key, sample in
            BurnWindowOutcome(providerID: key.provider, accountID: key.account, windowType: key.type,
                              bucketKey: key.bucket, resetAt: key.reset,
                              finalUsedPercent: min(100, max(0, sample.usedPercent)))
        }.sorted { $0.resetAt == $1.resetAt ? $0.id < $1.id : $0.resetAt < $1.resetAt }
    }
}
