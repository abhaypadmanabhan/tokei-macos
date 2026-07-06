import Foundation

public actor UsageStore {
    public static let shared = UsageStore()

    private var snapshots: [ProviderID: ProviderSnapshot] = [:]

    public init() {}

    public func save(snapshot: ProviderSnapshot) {
        snapshots[snapshot.providerID] = snapshot
    }

    public func save(snapshots: [ProviderSnapshot]) {
        for snapshot in snapshots {
            self.snapshots[snapshot.providerID] = snapshot
        }
    }

    public func snapshot(providerID: ProviderID) -> ProviderSnapshot? {
        snapshots[providerID]
    }

    public func allSnapshots() -> [ProviderSnapshot] {
        Array(snapshots.values)
    }
}
