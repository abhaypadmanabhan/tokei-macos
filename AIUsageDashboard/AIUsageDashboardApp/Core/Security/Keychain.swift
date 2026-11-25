import Foundation
import Security

public enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case conversionFailed
}

/// Secrets the person pastes into Settings (the official sign-ins), kept only in Tokei's
/// own Keychain service. Providers read through this seam so tests inject an in-memory
/// fake and never touch the real Keychain.
///
/// SECURITY: implementations must never log, print or persist a secret anywhere else.
public protocol SecretStore: Sendable {
    /// The stored secret, or `nil` when none is saved.
    func secret(for account: String) async throws -> String?
    /// Whether a secret is saved, without returning it.
    func hasSecret(for account: String) async throws -> Bool
    /// Saves or replaces the secret.
    func setSecret(_ secret: String, for account: String) async throws
    /// Deletes the secret; deleting a missing one is not an error.
    func removeSecret(for account: String) async throws
}

public actor Keychain {
    public static let shared = Keychain()
    public static let service = "ai.AIUsageDashboard"

    private let service: String

    /// `service` is fixed in the app; it is a parameter only so a manual proof can use a
    /// throwaway service instead of Tokei's real one.
    public init(service: String = Keychain.service) {
        self.service = service
    }

    /// Adds the item, or updates its data when one already exists for `account`.
    public func save(password: String, account: String) throws {
        let data = Data(password.utf8)
        var add = baseQuery(account: account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func retrieve(account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.itemNotFound : KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.conversionFailed
        }
        return password
    }

    /// Whether an item exists, asking for attributes only so the secret never loads.
    public func contains(account: String) throws -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return true
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

extension Keychain: SecretStore {
    public func secret(for account: String) throws -> String? {
        do {
            return try retrieve(account: account)
        } catch KeychainError.itemNotFound {
            return nil
        }
    }

    public func hasSecret(for account: String) throws -> Bool {
        try contains(account: account)
    }

    public func setSecret(_ secret: String, for account: String) throws {
        try save(password: secret, account: account)
    }

    public func removeSecret(for account: String) throws {
        try delete(account: account)
    }
}

/// The two official, opt-in sign-ins: a credential the person pastes, its Keychain account
/// name, and the live switch that must also be on before any request is made.
public enum OfficialSignIn: String, CaseIterable, Sendable {
    /// GitHub fine-grained personal access token with the user "Plan" permission (read).
    case githubBilling
    /// OpenCode Go API key.
    case opencodeGo

    public var providerID: ProviderID {
        switch self {
        case .githubBilling: return .copilot
        case .opencodeGo: return .opencode
        }
    }

    public init?(providerID: ProviderID) {
        guard let match = Self.allCases.first(where: { $0.providerID == providerID }) else { return nil }
        self = match
    }

    /// Keychain account under `Keychain.service`.
    public var keychainAccount: String {
        switch self {
        case .githubBilling: return "github.billing.token"
        case .opencodeGo: return "opencode.go.apiKey"
        }
    }

    /// UserDefaults switch, off unless the person turns it on.
    public var liveEnabledKey: String {
        switch self {
        case .githubBilling: return "copilotLiveBillingEnabled"
        case .opencodeGo: return "opencodeGoLiveQuotaEnabled"
        }
    }

    /// Prefix on every warning this sign-in produces, so Settings can show the latest one
    /// beside the field without parsing anything else.
    public var warningPrefix: String {
        switch self {
        case .githubBilling: return "GitHub billing:"
        case .opencodeGo: return "OpenCode Go:"
        }
    }
}
