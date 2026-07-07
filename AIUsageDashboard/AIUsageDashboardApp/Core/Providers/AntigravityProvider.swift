import Foundation

public actor AntigravityProvider: UsageProvider {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"

    public nonisolated var capabilities: ProviderCapabilities {
        if userDefaultsReader.bool(forKey: "antigravityOnlineQuotaEnabled") {
            return [.localLog, .quota, .providerEndpoint]
        }
        return [.localLog]
    }

    private let fileManager: FileManager
    private let stateDatabaseURL: URL
    private let parser: AntigravityStateDBParser
    private let quotaClient: AntigravityQuotaClient
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: AntigravityStateDBParser = .init(),
        quotaClient: AntigravityQuotaClient? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
        self.parser = parser
        self.quotaClient = quotaClient ?? AntigravityQuotaClientImpl()
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .authenticated : .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)
        var quotaWindows: [QuotaWindow] = []

        if userDefaultsReader.bool(forKey: "antigravityOnlineQuotaEnabled") {
            quotaWindows = (try? await quotaClient.fetchQuotaWindows()) ?? []
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: quotaWindows,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: warnings(from: state, hasLiveQuota: !quotaWindows.isEmpty),
            lastSyncedAt: Date()
        )
    }

    private func warnings(from state: AntigravityStateDBParser.ParsedState, hasLiveQuota: Bool) -> [ProviderWarning] {
        var warnings = state.warnings

        if let planName = state.planName, !planName.isEmpty {
            warnings.append(ProviderWarning(message: "Plan: \(planName)", level: .info))
        }

        // `availableCredits` is a real local number, but it is NOT the "Model Quota"
        // (per-model weekly / 5-hour limits) users see in the Antigravity app — that
        // data is fetched live from Google's backend and is not written to local
        // storage, so Tokei cannot show it offline. Surface the credits honestly and
        // say so, rather than fabricating a quota gauge from unrelated numbers.
        if let availableCredits = state.availableCredits {
            warnings.append(ProviderWarning(
                message: "Antigravity: \(availableCredits) model credits available (local).",
                level: .info
            ))
        }
        if !hasLiveQuota {
            warnings.append(ProviderWarning(
                message: "Model quota (weekly / 5-hour limits) is only shown in the Antigravity app; it is not stored locally, so Tokei can't read it offline.",
                level: .info
            ))
        }

        return warnings
    }
}

private final class ProviderUserDefaultsReader: @unchecked Sendable {
    private let userDefaults: UserDefaults

    init(_ userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func bool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }
}
