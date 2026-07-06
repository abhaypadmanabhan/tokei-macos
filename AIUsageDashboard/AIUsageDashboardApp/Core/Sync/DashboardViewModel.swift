import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var snapshots: [ProviderSnapshot] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    private let syncEngine: SyncEngine

    public init(syncEngine: SyncEngine = .shared) {
        self.syncEngine = syncEngine
    }

    public func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            snapshots = await syncEngine.refreshAll()
        }
        isLoading = false
    }
}
