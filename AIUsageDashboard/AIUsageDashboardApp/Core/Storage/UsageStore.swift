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

        let data: Data
        do {
            data = try JSONEncoder().encode(container)
        } catch {
            Self.logger.error("Failed to encode usage store: \(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            Self.logger.error("Failed to create usage store directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        let tempURL = directory.appendingPathComponent(fileName + ".tmp")
        do {
            try data.write(to: tempURL, options: .atomic)

            let fileExisted = FileManager.default.fileExists(atPath: fileURL.path)
            if !fileExisted {
                // Create a placeholder with restricted permissions so the atomic
                // replace below yields a new file that is readable only by the owner.
                guard FileManager.default.createFile(
                    atPath: fileURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    Self.logger.error("Failed to create usage store placeholder")
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
            }

            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            Self.logger.error("Failed to persist usage store: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tempURL)
        }
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
}

private struct DailyUsageKey: Hashable, Codable {
    let providerID: ProviderID
    let day: Date
}

