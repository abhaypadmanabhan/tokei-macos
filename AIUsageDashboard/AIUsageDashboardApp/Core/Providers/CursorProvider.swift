import Foundation

public actor CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor
    public let displayName: String = "Cursor"

    public nonisolated var capabilities: ProviderCapabilities {
        if userDefaultsReader.bool(forKey: "cursorNetworkUsageEnabled") {
            return [.localLog, .quota, .tokenUsage, .providerEndpoint]
        }
        return [.localLog]
    }

    private let fileManager: FileManager
    private let stateDatabaseURL: URL
    private let parser: CursorStateDBParser
    private let usageClient: CursorUsageClient
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: CursorStateDBParser = .init(),
        usageClient: CursorUsageClient? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        self.parser = parser
        self.usageClient = usageClient ?? CursorUsageClientImpl()
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)
        return state.isAuthenticated ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)
        var warnings = state.warnings

        var quotaWindows: [QuotaWindow] = []

        if userDefaultsReader.bool(forKey: "cursorNetworkUsageEnabled") {
            if let token = await parser.readAccessToken(stateDatabaseURL: stateDatabaseURL) {
                do {
                    let response = try await usageClient.fetchUsage(bearerToken: token)
                    quotaWindows = response.quotaWindows
                    warnings.append(contentsOf: response.warnings)
                } catch {
                    warnings.append(ProviderWarning(
                        message: "Cursor online usage request failed: \(error.localizedDescription). Falling back to offline data.",
                        level: .warning
                    ))
                }

                if let stripeProfile = try? await usageClient.fetchStripeProfile(bearerToken: token) {
                    warnings.removeAll { warning in
                        warning.level == .info && warning.message.hasPrefix("Plan: ")
                    }
                    warnings.append(stripeProfile.planWarning)
                }
            } else {
                warnings.append(ProviderWarning(
                    message: "Cursor online usage is enabled but no access token was found.",
                    level: .warning
                ))
            }
        }

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: state.isAuthenticated ? .authenticated : .unauthenticated,
            quotaWindows: quotaWindows,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: warnings,
            lastSyncedAt: Date(),
            dailyTotals: state.acceptedLinesByDate.isEmpty ? nil : state.acceptedLinesByDate
        )
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
