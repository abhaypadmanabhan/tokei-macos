import Foundation

/// Surfaces Gemini CLI quota. Detection is purely the presence of the CLI's
/// `~/.gemini/oauth_creds.json`; live quota comes from the Code Assist backend via
/// `GeminiUsageClientImpl`. The provider never throws for a quota failure — it always
/// resolves to a clean snapshot with an actionable `ProviderWarning`.
public actor GeminiProvider: UsageProvider {
    public let id: ProviderID = .gemini
    public let displayName: String = "Gemini"

    public nonisolated var capabilities: ProviderCapabilities {
        [.quota, .providerEndpoint]
    }

    private let fileManager: FileManager
    private let credentialsFileURL: URL
    private let quotaClient: any QuotaProvider

    public init(
        fileManager: FileManager = .default,
        credentialsFileURL: URL? = nil,
        quotaClient: (any QuotaProvider)? = nil
    ) {
        self.fileManager = fileManager
        let credentialsURL = credentialsFileURL
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/oauth_creds.json")
        self.credentialsFileURL = credentialsURL
        self.quotaClient = quotaClient ?? GeminiUsageClientImpl(credentialsFileURL: credentialsURL)
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: credentialsFileURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        fileManager.fileExists(atPath: credentialsFileURL.path) ? .authenticated : .unauthenticated
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        guard fileManager.fileExists(atPath: credentialsFileURL.path) else {
            return snapshot(authStatus: .unauthenticated, windows: [], warnings: [notSignedInWarning])
        }

        do {
            let windows = try await quotaClient.fetchQuotaWindows()
            var warnings: [ProviderWarning] = []
            if windows.isEmpty {
                warnings.append(ProviderWarning(
                    message: "Gemini is signed in, but Google returned no quota windows.",
                    level: .info
                ))
            }
            return snapshot(authStatus: .authenticated, windows: windows, warnings: warnings)
        } catch GeminiUsageError.notAuthenticated {
            // Creds file present but empty/malformed/token-less: this is NOT signed in.
            // authStatus must agree with the warning (Greptile P2 — was reporting
            // .authenticated while the warning said "not signed in").
            return snapshot(authStatus: .unauthenticated, windows: [], warnings: [notSignedInWarning])
        } catch {
            return snapshot(authStatus: .authenticated, windows: [], warnings: [warning(for: error)])
        }
    }

    private func snapshot(
        authStatus: AuthStatus,
        windows: [QuotaWindow],
        warnings: [ProviderWarning]
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: authStatus,
            quotaWindows: windows,
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: warnings,
            lastSyncedAt: Date()
        )
    }

    private var notSignedInWarning: ProviderWarning {
        ProviderWarning(
            message: "Gemini CLI isn't signed in on this Mac. Run `gemini` and sign in to show quota.",
            level: .info
        )
    }

    private func warning(for error: Error) -> ProviderWarning {
        switch error {
        case GeminiUsageError.notAuthenticated:
            return notSignedInWarning
        case GeminiUsageError.tokenRefreshUnavailable:
            return ProviderWarning(
                message: "Gemini access token has expired. Run `gemini` once to refresh it, then Tokei can read quota again.",
                level: .info
            )
        default:
            return ProviderWarning(
                message: "Couldn't read Gemini quota right now (Google endpoint error). Tokei will retry on the next sync.",
                level: .warning
            )
        }
    }
}
