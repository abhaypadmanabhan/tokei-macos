import Foundation

// MARK: - Threshold Logic

public struct FiredNotificationKey: Sendable {
    public let providerID: ProviderID
    public let windowType: QuotaWindowType
    public let threshold: Int
    public var resetAt: Date?
    public let bucketKey: String?
    public let accountID: String?

    public init(
        providerID: ProviderID, windowType: QuotaWindowType, threshold: Int, resetAt: Date? = nil,
        bucketKey: String? = nil, accountID: String? = nil
    ) {
        self.providerID = providerID
        self.windowType = windowType
        self.threshold = threshold
        self.resetAt = resetAt
        self.bucketKey = bucketKey
        self.accountID = accountID
    }

    func migrateLegacy(from legacy: Set<Self>, into fired: inout Set<Self>) {
        guard let previous = legacy.first(where: {
            $0.providerID == providerID && $0.windowType == windowType && $0.threshold == threshold
        }) else { return }
        fired.remove(previous)
        var scoped = self
        scoped.resetAt = previous.resetAt
        fired.update(with: scoped)
    }
}

extension FiredNotificationKey: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(providerID)
        hasher.combine(windowType)
        hasher.combine(threshold)
        hasher.combine(bucketKey)
        hasher.combine(accountID)
    }

    public static func == (lhs: FiredNotificationKey, rhs: FiredNotificationKey) -> Bool {
        lhs.providerID == rhs.providerID &&
        lhs.windowType == rhs.windowType &&
        lhs.threshold == rhs.threshold && lhs.bucketKey == rhs.bucketKey && lhs.accountID == rhs.accountID
    }
}

public struct ThresholdEvaluation: Equatable, Sendable {
    public let providerID: ProviderID
    public let windowType: QuotaWindowType
    public let threshold: Int
    public let percent: Double
    public let resetAt: Date?
    public let displayName: String
    let key: FiredNotificationKey
}

/// Pure, stateless evaluator for threshold crossing / re-arm logic.
public struct ThresholdEvaluator: Sendable {
    public static let thresholds: [Int] = [80, 95]

    /// Returns notifications that should fire and the updated set of armed thresholds.
    public static func evaluate(
        snapshots: [ProviderSnapshot],
        clock: Clock,
        previouslyFired: Set<FiredNotificationKey>,
        thresholdsByProvider: [ProviderID: [Int]] = [:]
    ) -> (notifications: [ThresholdEvaluation], fired: Set<FiredNotificationKey>) {
        let now = clock.now()
        var fired = previouslyFired.filter { $0.resetAt.map { $0 > now } ?? true }
        let legacy = fired.filter { $0.bucketKey == nil && $0.accountID == nil && $0.resetAt != nil }
        var notifications: [ThresholdEvaluation] = []

        for snapshot in snapshots {
            for window in snapshot.quotaWindows {
                guard !window.isInformationalCredits,
                      let used = window.used, let limit = window.limit, limit > 0 else { continue }
                guard window.confidence != .unavailable else { continue }
                let percent = (used / limit) * 100.0
                guard percent.isFinite else { continue }

                for threshold in thresholdsByProvider[snapshot.providerID] ?? thresholds {
                    let key = FiredNotificationKey(
                        providerID: window.providerID,
                        windowType: window.type,
                        threshold: threshold,
                        bucketKey: window.bucketKey,
                        accountID: snapshot.accounts?.first { $0.id == snapshot.headlineAccountID }?.accountID
                    )

                    key.migrateLegacy(from: legacy, into: &fired)
                    // Re-arm if usage has dropped back below the threshold.
                    if percent < Double(threshold) {
                        fired.remove(key)
                    }

                    if percent >= Double(threshold), !fired.contains(key) {
                        notifications.append(ThresholdEvaluation(
                            providerID: window.providerID,
                            windowType: window.type,
                            threshold: threshold,
                            percent: percent,
                            resetAt: window.resetAt,
                            displayName: snapshot.displayName,
                            key: key
                        ))
                        var keyToStore = key
                        keyToStore.resetAt = window.resetAt
                        fired.insert(keyToStore)
                    }
                }
            }
        }

        return (notifications, fired)
    }
}
