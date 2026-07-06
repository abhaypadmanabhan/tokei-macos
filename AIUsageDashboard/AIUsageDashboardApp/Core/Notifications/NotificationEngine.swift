import Foundation
import UserNotifications

public actor NotificationEngine {
    public static let shared = NotificationEngine()

    public init() {}

    public func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func evaluateThresholds(for snapshots: [ProviderSnapshot]) async {
        // TODO: Compare quota windows against user-defined thresholds and emit notifications.
    }
}
