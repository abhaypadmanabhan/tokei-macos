import Foundation
import os

public actor UsageStore {
    public static let shared = UsageStore()

    private static let logger = Logger(subsystem: "ai.padzy.tokei", category: "UsageStore")

    private var snapshots: [ProviderID: ProviderSnapshot] = [:]
    private var dailyUsages: [DailyUsageKey: DailyUsage] = [:]

    private let directory: URL
    private let fileName: String
    private var didLoad = false
    private var lastWrittenContent: Data?

    public init(directory: URL? = nil, fileName: String = "usage-store.json") {
        if let directory {
            self.directory = directory
        } else {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls.first ?? FileManager.default.temporaryDirectory
            self.directory = appSupport.appendingPathComponent("AIUsageDashboard", isDirectory: true)
        }
        self.fileName = fileName
        do {
            try SecureFileWriter.hardenExistingDirectory(at: self.directory)
        } catch {
            Self.logger.error("Failed to secure usage directory: \(error.localizedDescription, privacy: .public)")
        }
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
            lastWrittenContent = try? Self.encoder(ignoringSyncTime: true).encode(container)
        }
    }

    // Saved lastSyncedAt/observedAt mean last content change; WP-3 hydration must preserve their age.
    private func persist() {
        let today = DateHelpers.startOfToday()
        if let oldest = Calendar.current.date(byAdding: .day, value: -399, to: today) {
            dailyUsages = dailyUsages.filter { $0.key.day >= oldest }
        }
        let container = PersistenceContainer(snapshots: snapshots, dailyUsages: dailyUsages)

        let data: Data
        do {
            let content = try Self.encoder(ignoringSyncTime: true).encode(container)
            guard content != lastWrittenContent else { return }
            data = try Self.encoder().encode(container)
            try SecureFileWriter.write(data, to: fileURL)
            lastWrittenContent = content
        } catch {
            Self.logger.error("Failed to persist usage store: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func encoder(ignoringSyncTime: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.userInfo[.ignoringSyncTime] = ignoringSyncTime
        return encoder
    }

    private func upsertDailyUsage(from snapshot: ProviderSnapshot) {
        // Per-day usage, NOT lifetime cumulative: lifetime shrinks when old logs
        // rotate away, which would corrupt the history this exists to preserve.
        let usage = snapshot.todayUsage
        guard usage.totalTokens != nil else { return }
        let today = DateHelpers.startOfToday()
        let key = DailyUsageKey(providerID: snapshot.providerID, day: today)
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

    private enum CodingKeys: String, CodingKey { case snapshots, dailyUsages }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var storedSnapshots = container.nestedUnkeyedContainer(forKey: .snapshots)
        for key in snapshots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            try storedSnapshots.encode(key)
            try storedSnapshots.encode(snapshots[key])
        }
        var history = container.nestedUnkeyedContainer(forKey: .dailyUsages)
        let keys = dailyUsages.keys.sorted {
            ($0.providerID.rawValue, $0.day) < ($1.providerID.rawValue, $1.day)
        }
        for key in keys {
            try history.encode(key)
            try history.encode(dailyUsages[key])
        }
    }
}
private struct DailyUsageKey: Hashable, Codable {
    let providerID: ProviderID
    let day: Date
}
