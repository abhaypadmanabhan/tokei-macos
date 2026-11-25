import Foundation

public actor ProviderRegistry {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static func `default`() -> ProviderRegistry {
        ProviderRegistry(providers: [
            // Every Claude account on this machine, not just `~/.claude` — see `ClaudeAccount`.
            ClaudeCodeProvider(accounts: []),
            CodexProvider(liveQuotaClient: CodexRateLimitClient()),
            CursorProvider(),
            ClineProvider(),
            AntigravityProvider(),
            OpencodeProvider(),
            GeminiProvider(),
            CopilotProvider(),
            GrokProvider()
        ])
    }

    public func snapshotAll() async -> [ProviderSnapshot] {
        await snapshots(for: nil)
    }

    func snapshots(for providerIDs: Set<ProviderID>?, userInitiated: Bool = false) async -> [ProviderSnapshot] {
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            for provider in providers where providerIDs?.contains(provider.id) ?? true {
                group.addTask {
                    if userInitiated, let aware = provider as? UserRefreshAwareProvider {
                        await aware.prepareForUserRefresh()
                    }
                    PerformanceProbe.emit("provider_refresh", fields: ["provider": provider.id.rawValue])
                    do {
                        return try await provider.fetchSnapshot()
                    } catch {
                        return ProviderSnapshot(
                            providerID: provider.id,
                            displayName: provider.displayName,
                            authStatus: .error,
                            todayUsage: .unavailable,
                            weekUsage: .unavailable,
                            warnings: [ProviderWarning(
                                message: "Sync error: \(error.localizedDescription)",
                                level: .error
                            )]
                        )
                    }
                }
            }
            var snapshots: [ProviderSnapshot] = []
            for await snapshot in group {
                snapshots.append(snapshot)
            }
            return snapshots
        }
    }
}
