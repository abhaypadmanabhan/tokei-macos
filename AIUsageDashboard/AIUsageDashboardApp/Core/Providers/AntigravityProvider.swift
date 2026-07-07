import Foundation

public actor AntigravityProvider: UsageProvider {
    public let id: ProviderID = .antigravity
    public let displayName: String = "Antigravity"
    public let capabilities: ProviderCapabilities = [.localLog]

    private let fileManager: FileManager
    private let stateDatabaseURL: URL
    private let parser: AntigravityStateDBParser

    public init(
        fileManager: FileManager = .default,
        stateDatabaseURL: URL? = nil,
        parser: AntigravityStateDBParser = .init()
    ) {
        self.fileManager = fileManager
        self.stateDatabaseURL = stateDatabaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
        self.parser = parser
    }

    public func detectAvailability() async -> ProviderAvailability {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .installed : .notInstalled
    }

    public func authenticate() async throws -> AuthStatus {
        fileManager.fileExists(atPath: stateDatabaseURL.path) ? .authenticated : .unknown
    }

    public func fetchSnapshot() async throws -> ProviderSnapshot {
        let state = await parser.parse(stateDatabaseURL: stateDatabaseURL)

        return ProviderSnapshot(
            providerID: id,
            displayName: displayName,
            authStatus: try await authenticate(),
            quotaWindows: [],
            todayUsage: .unavailable,
            weekUsage: .unavailable,
            monthUsage: nil,
            lifetimeUsage: nil,
            costUsage: nil,
            warnings: warnings(from: state),
            lastSyncedAt: Date()
        )
    }

    private func warnings(from state: AntigravityStateDBParser.ParsedState) -> [ProviderWarning] {
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
        warnings.append(ProviderWarning(
            message: "Model quota (weekly / 5-hour limits) is only shown in the Antigravity app; it is not stored locally, so Tokei can't read it offline.",
            level: .info
        ))

        return warnings
    }
}
