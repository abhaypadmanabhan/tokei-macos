import Foundation

public actor UsageStore {
    public static let shared = UsageStore()

    private var snapshots: [ProviderID: ProviderSnapshot] = [:]
    private var dailyUsages: [DailyUsageKey: DailyUsage] = [:]

    private let directory: URL
    private let fileName: String
    private var didLoad = false

    public init(directory: URL? = nil, fileName: String = "usage-store.json") {
        if let directory {
            self.directory = directory
        } else {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls.first ?? FileManager.default.temporaryDirectory
            self.directory = appSupport.appendingPathComponent("AIUsageDashboard", isDirectory: true)
        }
        self.fileName = fileName
    }

    private var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        if let data = try? Data(contentsOf: fileURL),
           let container = try? JSONDecoder().decode(PersistenceContainer.self, from: data) {
            snapshots = container.snapshots
            dailyUsages = container.dailyUsages
        }
    }

    private func persist() {
        let container = PersistenceContainer(snapshots: snapshots, dailyUsages: dailyUsages)
        guard let data = try? JSONEncoder().encode(container) else { return }

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let tempURL = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func upsertDailyUsage(from snapshot: ProviderSnapshot) {
        let today = DateHelpers.startOfToday()
        let key = DailyUsageKey(providerID: snapshot.providerID, day: today)
        let usage = snapshot.lifetimeUsage ?? snapshot.todayUsage
        dailyUsages[key] = DailyUsage(
            date: today,
            providerID: snapshot.providerID,
            tokenUsage: usage
        )
    }

    public func save(snapshot: ProviderSnapshot) {
        ensureLoaded()
        snapshots[snapshot.providerID] = snapshot
        upsertDailyUsage(from: snapshot)
        persist()
    }

    public func save(snapshots: [ProviderSnapshot]) {
        ensureLoaded()
        for snapshot in snapshots {
            self.snapshots[snapshot.providerID] = snapshot
            upsertDailyUsage(from: snapshot)
        }
        persist()
    }

    public func snapshot(providerID: ProviderID) -> ProviderSnapshot? {
        ensureLoaded()
        return snapshots[providerID]
    }

    public func allSnapshots() -> [ProviderSnapshot] {
        ensureLoaded()
        return Array(snapshots.values)
    }

    public func dailyHistory(providerID: ProviderID) -> [DailyUsage] {
        ensureLoaded()
        return dailyUsages
            .filter { $0.key.providerID == providerID }
            .map { $0.value }
            .sorted { $0.date < $1.date }
    }
}

private struct PersistenceContainer: Codable {
    var snapshots: [ProviderID: ProviderSnapshot]
    var dailyUsages: [DailyUsageKey: DailyUsage]
}

private struct DailyUsageKey: Hashable, Codable {
    let providerID: ProviderID
    let day: Date
}

