import Foundation
import UserNotifications

// MARK: - Clock

/// Injectable source of "now" so threshold logic can be tested deterministically.
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

// MARK: - Notification Center

/// Abstracted notification center so tests never touch the real UNUserNotificationCenter.
public protocol UserNotificationCenter: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(request: NotificationRequest) async throws
}

/// Value-type description of a notification to deliver.
public struct NotificationRequest: Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let sound: Bool

    public init(identifier: String, title: String, body: String, sound: Bool) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.sound = sound
    }
}

// MARK: - Notification Engine

public actor NotificationEngine {
    public static let shared = NotificationEngine()

    public static let notificationThresholds: [Int] = ThresholdEvaluator.thresholds
    public static let notificationsEnabledKey = "notificationsEnabled"
    private static let firedKeysDefaultsKey = "notificationThresholdFiredKeys"
    private static let predictiveKeysDefaultsKey = "predictiveQuotaWarningFiredKeys"

    private let notificationCenter: UserNotificationCenter
    private let clock: Clock
    private let userDefaults: UserDefaults
    private var firedKeys: Set<FiredNotificationKey>
    private var predictiveKeys: Set<PredictiveQuotaWarning.Key>
    private var isEvaluating = false
    private static let burnStateKey = "burnNotificationState"
    private var burnState: BurnNudgeState
    private var isEvaluatingBurn = false

    public init(
        notificationCenter: UserNotificationCenter = UserNotificationCenterWrapper(),
        clock: Clock = SystemClock(),
        userDefaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.clock = clock
        self.userDefaults = userDefaults
        self.firedKeys = Self.loadFiredKeys(from: userDefaults)
        self.burnState = userDefaults.data(forKey: Self.burnStateKey).flatMap {
            try? JSONDecoder().decode(BurnNudgeState.self, from: $0)
        } ?? BurnNudgeState()
        self.predictiveKeys = userDefaults.data(forKey: Self.predictiveKeysDefaultsKey).flatMap {
            try? JSONDecoder().decode(Set<PredictiveQuotaWarning.Key>.self, from: $0)
        } ?? []
    }

    public func evaluateThresholds(for snapshots: [ProviderSnapshot]) async {
        let enabled = userDefaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
        guard enabled, !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        let thresholds = Dictionary(snapshots.map {
            ($0.providerID, Self.thresholds(for: $0.providerID, defaults: userDefaults))
        }, uniquingKeysWith: { first, _ in first })

        let result = ThresholdEvaluator.evaluate(
            snapshots: snapshots,
            clock: clock,
            previouslyFired: firedKeys,
            thresholdsByProvider: thresholds
        )
        let now = clock.now()
        predictiveKeys = predictiveKeys.filter {
            $0.resetAt.addingTimeInterval(PredictiveQuotaWarning.Key.resetTolerance) > now
        }
        let predictiveEnabled = userDefaults.object(forKey: "predictiveQuotaWarningsEnabled") as? Bool ?? true
        let predictions = predictiveEnabled ? PredictiveQuotaWarning.evaluate(snapshots: snapshots, now: now)
            .filter { !hasFiredPrediction($0.key, at: now) } : []

        guard !result.notifications.isEmpty || !predictions.isEmpty else {
            firedKeys = result.fired
            Self.saveFiredKeys(firedKeys, to: userDefaults)
            return
        }

        // Lazy authorization: only ask the user when we actually have something to say.
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            guard granted else { return }
        } catch {
            return
        }

        firedKeys = result.fired
        await deliver(thresholds: result.notifications, predictions: predictions)
    }

    /// Quiet burn notifications share one persisted cap per local day. Failed or denied
    /// deliveries never consume that cap or suppress a later successful attempt.
    public func evaluateBurn(_ snapshot: BurnSnapshot, calendar: Calendar = .current) async {
        guard burnNotificationsEnabled, !isEvaluatingBurn else { return }
        isEvaluatingBurn = true
        defer { isEvaluatingBurn = false }
        let now = clock.now()
        burnState.advance(to: now, calendar: calendar)
        guard burnState.count < BurnNudgePolicy.maxPerDay,
              !BurnNudge.candidates(snapshot: snapshot, delivered: burnState.delivered, now: now).isEmpty else { return }
        do {
            guard try await notificationCenter.requestAuthorization(options: [.alert]) else { return }
        } catch { return }
        let deliveryTime = clock.now()
        burnState.advance(to: deliveryTime, calendar: calendar)
        let candidates = BurnNudge.candidates(snapshot: snapshot, delivered: burnState.delivered, now: deliveryTime)
        for candidate in candidates {
            guard burnNotificationsEnabled, burnState.count < BurnNudgePolicy.maxPerDay else { break }
            let request = NotificationRequest(identifier: "burn_" + candidate.key,
                                              title: "Tokei", body: candidate.body, sound: false)
            do {
                try await notificationCenter.add(request: request)
                burnState.count += 1
                burnState.delivered[candidate.key] = deliveryTime
                if let data = try? JSONEncoder().encode(burnState) {
                    userDefaults.set(data, forKey: Self.burnStateKey)
                }
            } catch { continue }
        }
    }

    private var burnNotificationsEnabled: Bool {
        (userDefaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true) &&
            (userDefaults.object(forKey: BurnNudgePolicy.enabledKey) as? Bool ?? true)
    }

    private func deliver(thresholds: [ThresholdEvaluation], predictions: [PredictiveQuotaWarning]) async {
        for evaluation in thresholds {
            let request = NotificationRequest(
                identifier: "\(evaluation.providerID.rawValue)_\(evaluation.threshold)_\(UUID().uuidString)",
                title: "Tokei",
                body: Self.body(for: evaluation),
                sound: true
            )
            do { try await notificationCenter.add(request: request) } catch { firedKeys.remove(evaluation.key) }
        }
        for prediction in predictions {
            guard !hasFiredPrediction(prediction.key, at: clock.now()) else { continue }
            let request = NotificationRequest(
                identifier: "predictive_\(UUID().uuidString)", title: "Tokei", body: prediction.body, sound: true
            )
            do {
                try await notificationCenter.add(request: request)
                predictiveKeys.update(with: prediction.key)
            } catch { continue }
        }
        Self.saveFiredKeys(firedKeys, to: userDefaults)
        if let data = try? JSONEncoder().encode(predictiveKeys) {
            userDefaults.set(data, forKey: Self.predictiveKeysDefaultsKey)
        }
    }

    private func hasFiredPrediction(_ key: PredictiveQuotaWarning.Key, at now: Date) -> Bool {
        predictiveKeys.contains { $0.suppresses(key, now: now) }
    }

    private nonisolated static func thresholds(for provider: ProviderID, defaults: UserDefaults) -> [Int] {
        guard let values = defaults.object(forKey: "notificationThresholds.\(provider.rawValue)") as? [Int],
              values.count <= 4, values.allSatisfy({ (1...100).contains($0) }) else { return notificationThresholds }
        return Set(values).sorted()
    }

    private nonisolated static func body(for evaluation: ThresholdEvaluation) -> String {
        let resetString: String
        if let resetAt = evaluation.resetAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            resetString = formatter.string(from: resetAt)
        } else {
            resetString = "unknown"
        }
        return "\(evaluation.displayName) \(evaluation.windowType.rawValue) window at " +
            "\(Int(min(100, max(0, evaluation.percent))))% — resets \(resetString)"
    }

    private nonisolated static func loadFiredKeys(from defaults: UserDefaults) -> Set<FiredNotificationKey> {
        guard let data = defaults.data(forKey: firedKeysDefaultsKey),
              let decoded = try? JSONDecoder().decode(Set<FiredNotificationKey>.self, from: data) else {
            return []
        }
        return decoded
    }

    private nonisolated static func saveFiredKeys(_ keys: Set<FiredNotificationKey>, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(keys) {
            defaults.set(data, forKey: firedKeysDefaultsKey)
        }
    }
}

/// Real notification center wrapper. Marked `@unchecked Sendable` because
/// `UNUserNotificationCenter.current()` is a thread-safe singleton.
public struct UserNotificationCenterWrapper: UserNotificationCenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(request: NotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        if request.sound {
            content.sound = .default
        }
        let unRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: nil
        )
        try await center.add(unRequest)
    }
}
