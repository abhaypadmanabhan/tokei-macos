import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var snapshots: [ProviderSnapshot] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastSyncedAt: Date?

    private let syncEngine: SyncEngine

    public init(syncEngine: SyncEngine = .shared) {
        self.syncEngine = syncEngine
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        snapshots = await syncEngine.refreshAll()
        lastSyncedAt = Date()
        isLoading = false
    }

    public var claudeSnapshot: ProviderSnapshot? {
        snapshots.first { $0.providerID == .claudeCode }
    }

    public func snapshot(for providerID: ProviderID) -> ProviderSnapshot? {
        snapshots.first { $0.providerID == providerID }
    }
}
