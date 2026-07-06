import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var snapshots: [ProviderSnapshot] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var lastSyncedAt: Date?
    @Published public var selectedProvider: ProviderID = .claudeCode
    /// When true the dashboard's right pane shows the in-app Settings surface instead
    /// of the selected provider's usage. Shared so the menu-bar entry can drive it too.
    @Published public var showingSettings = false

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

    public func isAvailable(_ providerID: ProviderID) -> Bool {
        guard let snapshot = snapshot(for: providerID) else { return false }
        if providerID == .claudeCode {
            return true
        }
        let nonUnavailableQuotaWindows = snapshot.quotaWindows.filter { $0.confidence != .unavailable }
        let hasTokens = snapshot.todayUsage.totalTokens != nil && snapshot.todayUsage.confidence != .unavailable && snapshot.todayUsage.totalTokens! > 0
        let hasCost = snapshot.costUsage?.amount != nil && snapshot.costUsage?.confidence != .unavailable
        return hasTokens || !nonUnavailableQuotaWindows.isEmpty || hasCost
    }

    public func selectNextProvider() {
        let available = ProviderID.allCases.filter { isAvailable($0) }
        guard !available.isEmpty else { return }
        if let currentIndex = available.firstIndex(of: selectedProvider) {
            let nextIndex = (currentIndex + 1) % available.count
            selectedProvider = available[nextIndex]
        } else {
            selectedProvider = available.first ?? .claudeCode
        }
    }

    public func selectPreviousProvider() {
        let available = ProviderID.allCases.filter { isAvailable($0) }
        guard !available.isEmpty else { return }
        if let currentIndex = available.firstIndex(of: selectedProvider) {
            let prevIndex = (currentIndex - 1 + available.count) % available.count
            selectedProvider = available[prevIndex]
        } else {
            selectedProvider = available.first ?? .claudeCode
        }
    }

    public var menuBarTodayTotal: Int {
        snapshots.compactMap { isAvailable($0.providerID) ? $0.todayUsage.totalTokens : nil }.reduce(0, +)
    }
}

