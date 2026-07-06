import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var snapshots: [ProviderSnapshot] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastSyncedAt: Date?

    private let syncEngine: SyncEngine
    private var updatesTask: Task<Void, Never>?

    public init(syncEngine: SyncEngine = .shared) {
        self.syncEngine = syncEngine
    }

    deinit {
        updatesTask?.cancel()
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        snapshots = await syncEngine.refreshAll()
        lastSyncedAt = Date()
        isLoading = false
    }

    /// Starts the file watcher and subscribes to sync results so auto-refreshes
    /// (and refreshes triggered elsewhere) update this view model. Idempotent.
    public func beginAutoSync() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [syncEngine, weak self] in
            let stream = await syncEngine.updates
            await syncEngine.startAutoSync()
            for await snapshots in stream {
                guard let self else { return }
                await MainActor.run {
                    self.snapshots = snapshots
                    self.lastSyncedAt = Date()
                }
            }
        }
    }

    public var claudeSnapshot: ProviderSnapshot? {
        snapshots.first { $0.providerID == .claudeCode }
    }

    public func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        snapshots.first { $0.providerID == providerID }
    }
}
