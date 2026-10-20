import Foundation

/// Thread-safe read-only view over a `UserDefaults` suite, shared by providers that
/// gate optional online fetches on an opt-in toggle. `UserDefaults` is already
/// thread-safe, so the `@unchecked Sendable` wrapper just lets providers (actors)
/// hold it as a `nonisolated let`.
final class ProviderUserDefaultsReader: @unchecked Sendable {
    private let userDefaults: UserDefaults

    init(_ userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func bool(forKey key: String, defaultValue: Bool = false) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
}
