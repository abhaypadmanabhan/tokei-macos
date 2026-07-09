import Foundation

public actor ProviderRegistry {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static func `default`() -> ProviderRegistry {
        ProviderRegistry(providers: [
            ClaudeCodeProvider(),
            CodexProvider(),
            CursorProvider(),
            ClineProvider(),
            AntigravityProvider(),
            OpencodeProvider()
        ])
    }

    public func snapshotAll() async -> [ProviderSnapshot] {
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.fetchSnapshot()
                    } catch {
                        return ProviderSnapshot(
                            providerID: provider.id,
                            displayName: provider.displayName,
                            authStatus: .error,
                            todayUsage: .unavailable,
                            weekUsage: .unavailable,
                            warnings: [ProviderWarning(message: "Sync error: \(error.localizedDescription)", level: .error)]
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
