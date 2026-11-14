import Foundation

extension BurnEngine {
    /// Reset estimates jitter. Keep each account/series separate, then merge nearby reset
    /// readings into one instance before choosing its final pre-reset sample.
    static func windowOutcomes(samples: [QuotaSample], now: Date) -> [BurnWindowOutcome] {
        struct Series: Hashable {
            let provider: ProviderID
            let account: String?
            let type: QuotaWindowType
            let bucket: String
        }
        let accountProviders = Set(samples.filter { $0.accountID != nil }.map(\.providerID))
        var series: [Series: [QuotaSample]] = [:]
        for sample in samples {
            guard ExpiringHeadroomFinder.Policy.standard.horizon(for: sample.windowType) != nil,
                  sample.resetAt != nil, sample.usedPercent.isFinite,
                  sample.accountID != nil || !accountProviders.contains(sample.providerID) else { continue }
            let key = Series(provider: sample.providerID, account: sample.accountID,
                             type: sample.windowType, bucket: sample.bucketKey)
            series[key, default: []].append(sample)
        }
        var outcomes: [BurnWindowOutcome] = []
        for (key, readings) in series {
            let ordered = readings.sorted {
                if $0.resetAt != $1.resetAt { return ($0.resetAt ?? .distantPast) < ($1.resetAt ?? .distantPast) }
                return $0.sampledAt < $1.sampledAt
            }
            var instance: [QuotaSample] = []
            var reset: Date?
            func finishInstance() {
                guard let reset, reset <= now,
                      let last = instance.filter({ $0.sampledAt < reset }).max(by: { $0.sampledAt < $1.sampledAt }) else { return }
                outcomes.append(BurnWindowOutcome(providerID: key.provider, accountID: key.account,
                                                   windowType: key.type, bucketKey: key.bucket, resetAt: reset,
                                                   finalUsedPercent: min(100, max(0, last.usedPercent))))
            }
            for sample in ordered {
                guard let nextReset = sample.resetAt else { continue }
                if let reset, nextReset.timeIntervalSince(reset) > PredictiveQuotaWarning.Key.resetTolerance {
                    finishInstance()
                    instance.removeAll(keepingCapacity: true)
                }
                reset = nextReset // Sorted resets: the latest estimate defines this instance.
                instance.append(sample)
            }
            finishInstance()
        }
        return outcomes.sorted { $0.resetAt == $1.resetAt ? $0.id < $1.id : $0.resetAt < $1.resetAt }
    }
}
