import Foundation

/// Local opencode logs are the offline baseline. OpenCode Go's live limits come from the
/// official usage endpoint only when the person turned on `opencodeGoLiveQuotaEnabled` AND
/// saved a Go API key in Settings (Tokei's own Keychain).
public actor OpencodeProvider: UsageProvider, LocalLogProvider {
    public let id: ProviderID = .opencode
    public let displayName: String = "opencode"

    public nonisolated var capabilities: ProviderCapabilities {
        userDefaultsReader.bool(forKey: OfficialSignIn.opencodeGo.liveEnabledKey)
            ? [.localLog, .tokenUsage, .cost, .quota, .providerEndpoint]
            : [.localLog, .tokenUsage, .cost]
    }

    private let fileManager: FileManager
    private let parser: OpencodeStoreParser
    private let opencodeDirectory: URL
    private let goUsageClient: any OpencodeGoUsageFetching
    private let secretStore: any SecretStore
    private let now: @Sendable () -> Date
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        parser: OpencodeStoreParser = .init(),
        opencodeDirectory: URL? = nil,
        goUsageClient: (any OpencodeGoUsageFetching)? = nil,
        secretStore: (any SecretStore)? = nil,
        userDefaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.parser = parser
        self.opencodeDirectory = opencodeDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
        self.goUsageClient = goUsageClient ?? OpencodeGoUsageClient()
        self.secretStore = secretStore ?? Keychain.shared
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
        self.now = now
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: opencodeDirectory.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        let auth = opencodeDirectory.appendingPathComponent("auth.json")
        return fileManager.fileExists(atPath: auth.path) ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let usage = await parser.parse(rootDirectory: opencodeDirectory)
        var warnings = usage.warnings
        if usage.sourceKind == .none {
            warnings.append(ProviderWarning(message: "No opencode messages found", level: .info))
        }

        let costUsage: CostUsage
        if usage.totalCost > 0 {
            costUsage = CostUsage(amount: usage.totalCost, currency: "USD", confidence: .providerReported)
        } else {
            costUsage = CostUsage(confidence: .unavailable)
        }

        let live = await goQuota()
        warnings += live.warnings

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: live.windows,
            todayUsage: usage.today,
            weekUsage: usage.week,
            monthUsage: usage.month,
            lifetimeUsage: usage.lifetime,
            costUsage: costUsage,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: usage.dailyTotals,
            hourlyTotals: usage.hourlyTotals
        )
    }

    // MARK: - OpenCode Go (official usage endpoint)

    private func goQuota() async -> (windows: [QuotaWindow], warnings: [ProviderWarning]) {
        let signIn = OfficialSignIn.opencodeGo
        guard userDefaultsReader.bool(forKey: signIn.liveEnabledKey) else { return ([], []) }
        do {
            guard let apiKey = try await secretStore.secret(for: signIn.keychainAccount) else {
                throw OfficialUsageError.missingCredential
            }
            let meters = try await goUsageClient.fetchMeters(apiKey: apiKey)
            let windows = OpencodeGoUsageParser.quotaWindows(from: meters, observedAt: now())
            var warnings = meters.filter(\.isRateLimited).map { meter in
                let name = OpencodeGoUsageParser.label(meter.kind)
                return ProviderWarning(
                    message: "\(signIn.warningPrefix) \(name) limit is used up until it resets.",
                    level: .warning
                )
            }
            if windows.isEmpty {
                warnings.append(ProviderWarning(
                    message: "\(signIn.warningPrefix) the usage endpoint returned no limits.", level: .info
                ))
            }
            return (windows, warnings)
        } catch {
            return ([], [Self.goWarning(for: error)])
        }
    }

    static func goWarning(for error: Error) -> ProviderWarning {
        let prefix = OfficialSignIn.opencodeGo.warningPrefix
        switch error {
        case OfficialUsageError.missingCredential:
            return ProviderWarning(
                message: "\(prefix) live quota is on but no API key is saved. Paste one in Settings › Live quota.",
                level: .info
            )
        case OfficialUsageError.unauthorized:
            return ProviderWarning(
                message: "\(prefix) the saved API key was rejected (401)."
                    + " Copy a fresh key from the OpenCode Console.",
                level: .warning
            )
        case OfficialUsageError.forbidden(let message):
            return ProviderWarning(
                message: "\(prefix) \(message ?? "this key has no active Go subscription") (403).",
                level: .warning
            )
        case OfficialUsageError.cooldownActive, OfficialUsageError.rateLimited:
            return ProviderWarning(message: "\(prefix) rate limited, will retry later.", level: .info)
        case is KeychainError:
            return ProviderWarning(
                message: "\(prefix) could not read the saved key from the Keychain.", level: .warning
            )
        default:
            return ProviderWarning(
                message: "\(prefix) could not read usage right now (\(error.localizedDescription)).",
                level: .warning
            )
        }
    }

    public func discoverLogSources() async throws -> [LogSource] {
        try await parser.discoverLogSources(rootDirectory: opencodeDirectory)
    }
}
