import Foundation
import AIUsageDashboardCore

/// Quota-alert settings the Settings drawer writes and the notification engine reads (§4
/// contract 4): per-provider thresholds at `notificationThresholds.<providerID.rawValue>`
/// (`[Int]`, each 1…100, at most four, default `[80, 95]`) and the predictive-warning switch
/// `predictiveQuotaWarningsEnabled` (default on). Pure, so the Core test bundle compiles it.
enum AlertSettings {
    static let predictiveWarningsKey = "predictiveQuotaWarningsEnabled"
    static let defaultThresholds = [80, 95]
    static let maxThresholds = 4

    static func thresholdsKey(for providerID: ProviderID) -> String {
        "notificationThresholds.\(providerID.rawValue)"
    }

    /// The stored thresholds, or the default when unset or unusable.
    static func thresholds(for providerID: ProviderID, defaults: UserDefaults = .standard) -> [Int] {
        guard let stored = defaults.array(forKey: thresholdsKey(for: providerID)) as? [Int],
              let clean = sanitized(stored) else { return defaultThresholds }
        return clean
    }

    /// Writes thresholds that pass `sanitized`; `nil` (a blank field) clears the key so the
    /// provider goes back to the default. Returns what was stored.
    @discardableResult
    static func setThresholds(
        _ values: [Int]?,
        for providerID: ProviderID,
        defaults: UserDefaults = .standard
    ) -> [Int] {
        let key = thresholdsKey(for: providerID)
        guard let values, let clean = sanitized(values) else {
            defaults.removeObject(forKey: key)
            return defaultThresholds
        }
        defaults.set(clean, forKey: key)
        return clean
    }

    /// Ascending, without duplicates; `nil` unless every value is 1…100 and there are one
    /// to four of them.
    static func sanitized(_ values: [Int]) -> [Int]? {
        let unique = Array(Set(values)).sorted()
        guard !unique.isEmpty, unique.count <= maxThresholds,
              unique.allSatisfy({ (1...100).contains($0) }) else { return nil }
        return unique
    }

    /// "80, 95" or "80 95%" → [80, 95]; `nil` for anything that is not a usable list.
    static func parse(_ text: String) -> [Int]? {
        let parts = text
            .replacingOccurrences(of: "%", with: " ")
            .split(whereSeparator: { $0 == "," || $0 == " " })
        guard !parts.isEmpty else { return nil }
        var values: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            values.append(value)
        }
        return sanitized(values)
    }

    /// "80, 95": how a threshold list reads in the field.
    static func text(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ", ")
    }
}
