import Foundation

/// Surfaces the SuperGrok usage pool (shared by Grok chat, the Grok CLI and Cursor's Super
/// plan) from the Grok CLI's own billing call. Detection is the CLI's login file; the
/// network read is opt-in (`grokNetworkUsageEnabled`), like Cursor's and Claude's. The
/// provider never throws for a quota failure: it returns a snapshot with a plain warning.
public actor GrokProvider: UsageProvider {
    public static let networkUsageEnabledKey = "grokNetworkUsageEnabled"

    public let id: ProviderID = .grok
    public let displayName: String = "Grok"

    public nonisolated var capabilities: ProviderCapabilities { [.quota, .providerEndpoint] }

    private let fileManager: FileManager
    private let authFileURL: URL
    private let client: any GrokBillingClient
    private let now: @Sendable () -> Date
    private nonisolated let userDefaultsReader: ProviderUserDefaultsReader

    public init(
        fileManager: FileManager = .default,
        grokHome: URL? = nil,
        client: (any GrokBillingClient)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        userDefaults: UserDefaults = .standard
    ) {
        let home = grokHome ?? GrokBillingClientImpl.defaultGrokHome()
        self.fileManager = fileManager
        self.authFileURL = home.appendingPathComponent("auth.json")
        self.client = client ?? GrokBillingClientImpl(grokHome: home, now: now)
        self.now = now
        self.userDefaultsReader = ProviderUserDefaultsReader(userDefaults)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: authFileURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        fileManager.fileExists(atPath: authFileURL.path) ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        guard fileManager.fileExists(atPath: authFileURL.path) else {
            return snapshot(.unauthenticated, warnings: [Self.notSignedIn])
        }
        guard userDefaultsReader.bool(forKey: Self.networkUsageEnabledKey) else {
            return snapshot(.authenticated, warnings: [ProviderWarning(
                message: "Grok usage is off. Turn it on in Settings to show the SuperGrok pool.", level: .info
            )])
        }
        do {
            let body = try await client.fetchBilling()
            guard let summary = GrokBillingSummary.decode(body) else {
                return snapshot(.authenticated, warnings: [ProviderWarning(
                    message: Self.noReading, level: .warning
                )])
            }
            var warnings: [ProviderWarning] = []
            if let tier = summary.subscriptionTier {
                warnings.append(ProviderWarning(message: "Plan: \(tier)", level: .info))
            }
            let windows = summary.quotaWindows(observedAt: now())
            if windows.isEmpty {
                warnings.append(ProviderWarning(message: Self.noReading, level: .warning))
            }
            return snapshot(.authenticated, windows: windows, warnings: warnings)
        } catch GrokBillingError.notSignedIn {
            return snapshot(.unauthenticated, warnings: [Self.notSignedIn])
        } catch GrokBillingError.loginExpired {
            return snapshot(.unauthenticated, warnings: [ProviderWarning(
                message: "Grok CLI sign-in has expired. Run `grok` once to refresh it.", level: .warning
            )])
        } catch {
            return snapshot(.authenticated, warnings: [ProviderWarning(
                message: "Grok usage request failed: \(error.localizedDescription)", level: .warning
            )])
        }
    }

    private static let noReading = "Grok usage returned no SuperGrok pool reading."

    private static let notSignedIn = ProviderWarning(
        message: "Grok CLI isn't signed in on this Mac. Run `grok login` to show the SuperGrok pool.", level: .info
    )

    private func snapshot(
        _ authStatus: AuthStatus, windows: [QuotaWindow] = [], warnings: [ProviderWarning]
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id, displayName: displayName, authStatus: authStatus, quotaWindows: windows,
            todayUsage: .unavailable, weekUsage: .unavailable, warnings: warnings, lastSyncedAt: now()
        )
    }
}
