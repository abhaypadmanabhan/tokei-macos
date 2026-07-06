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

    private let notificationCenter: UserNotificationCenter
    private let clock: Clock
    private let userDefaults: UserDefaults
    private var firedKeys: Set<FiredNotificationKey>

    public init(
        notificationCenter: UserNotificationCenter = UserNotificationCenterWrapper(),
        clock: Clock = SystemClock(),
        userDefaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.clock = clock
        self.userDefaults = userDefaults
        self.firedKeys = Self.loadFiredKeys(from: userDefaults)
    }

    public func evaluateThresholds(for snapshots: [ProviderSnapshot]) async {
        let enabled = userDefaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
        guard enabled else { return }

        let result = ThresholdEvaluator.evaluate(
            snapshots: snapshots,
            clock: clock,
            previouslyFired: firedKeys
        )

        firedKeys = result.fired
        Self.saveFiredKeys(firedKeys, to: userDefaults)

        guard !result.notifications.isEmpty else { return }

        // Lazy authorization: only ask the user when we actually have something to say.
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            guard granted else { return }
        } catch {
            return
        }

        for evaluation in result.notifications {
            let request = NotificationRequest(
                identifier: "\(evaluation.providerID.rawValue)_\(evaluation.windowType.rawValue)_\(evaluation.threshold)_\(UUID().uuidString)",
                title: "Tokei",
                body: Self.body(for: evaluation),
                sound: true
            )
            try? await notificationCenter.add(request: request)
        }
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
        return "\(evaluation.displayName) \(evaluation.windowType.rawValue) window at \(Int(evaluation.percent))% — resets \(resetString)"
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

// MARK: - Threshold Logic

public struct FiredNotificationKey: Codable, Sendable {
    public let providerID: ProviderID
    public let windowType: QuotaWindowType
    public let threshold: Int
    public var resetAt: Date?

    public init(providerID: ProviderID, windowType: QuotaWindowType, threshold: Int, resetAt: Date? = nil) {
        self.providerID = providerID
        self.windowType = windowType
        self.threshold = threshold
        self.resetAt = resetAt
    }
}

extension FiredNotificationKey: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(providerID)
        hasher.combine(windowType)
        hasher.combine(threshold)
    }

    public static func == (lhs: FiredNotificationKey, rhs: FiredNotificationKey) -> Bool {
        lhs.providerID == rhs.providerID &&
        lhs.windowType == rhs.windowType &&
        lhs.threshold == rhs.threshold
    }
}

public struct ThresholdEvaluation: Equatable, Sendable {
    public let providerID: ProviderID
    public let windowType: QuotaWindowType
    public let threshold: Int
    public let percent: Double
    public let resetAt: Date?
    public let displayName: String
}

/// Pure, stateless evaluator for threshold crossing / re-arm logic.
public struct ThresholdEvaluator: Sendable {
    public static let thresholds: [Int] = [80, 95]

    /// Returns notifications that should fire and the updated set of armed thresholds.
    public static func evaluate(
        snapshots: [ProviderSnapshot],
        clock: Clock,
        previouslyFired: Set<FiredNotificationKey>
    ) -> (notifications: [ThresholdEvaluation], fired: Set<FiredNotificationKey>) {
        var fired = previouslyFired
        var notifications: [ThresholdEvaluation] = []
        let now = clock.now()

        for snapshot in snapshots {
            for window in snapshot.quotaWindows {
                guard let used = window.used, let limit = window.limit, limit > 0 else { continue }
                guard window.confidence != .unavailable else { continue }
                let percent = (used / limit) * 100.0

                for threshold in thresholds {
                    let key = FiredNotificationKey(
                        providerID: window.providerID,
                        windowType: window.type,
                        threshold: threshold
                    )

                    // Re-arm if the stored window reset has passed.
                    if let storedKey = fired.first(where: { $0 == key }),
                       let storedResetAt = storedKey.resetAt,
                       storedResetAt <= now {
                        fired.remove(key)
                    }
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
                            displayName: snapshot.displayName
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

