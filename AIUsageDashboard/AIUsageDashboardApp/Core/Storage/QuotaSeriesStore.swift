import Foundation

public actor QuotaSeriesStore {
    public static let shared = QuotaSeriesStore()

    /// Hard cap for retained quota samples. At the current file-watcher sync cadence
    /// this preserves a bounded recent history without allowing the sidecar to grow forever.
    public static let defaultRetentionLimit = 20_000

    private let now: @Sendable () -> Date
    private let directory: URL
    private let fileName: String
    private let retentionLimit: Int
    private var samples: [QuotaSample] = []
    private var didLoad = false

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        directory: URL? = nil,
        fileName: String = "quota-series.json",
        retentionLimit: Int = QuotaSeriesStore.defaultRetentionLimit
    ) {
        self.now = now
        if let directory {
            self.directory = directory
        } else {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = urls.first ?? FileManager.default.temporaryDirectory
            self.directory = appSupport.appendingPathComponent("AIUsageDashboard", isDirectory: true)
        }
        self.fileName = fileName
        self.retentionLimit = max(1, retentionLimit)
    }

    public func append(from snapshots: [ProviderSnapshot]) {
        ensureLoaded()
        let sampledAt = now()
        var didAppend = false

        for snapshot in snapshots {
            for window in snapshot.quotaWindows {
                guard let sample = QuotaSample(window: window, sampledAt: sampledAt) else {
                    continue
                }
                if let last = samples.last(where: { $0.isSameSeries(as: sample) }),
                   last.hasSameReading(as: sample) {
                    continue
                }
                samples.append(sample)
                didAppend = true
            }
        }

        guard didAppend else { return }
        enforceRetentionLimit()
        persist()
    }

    public func samples(
        for providerID: ProviderID,
        windowType: QuotaWindowType,
        since: Date? = nil
    ) -> [QuotaSample] {
        ensureLoaded()
        return samples
            .filter { sample in
                sample.providerID == providerID &&
                    sample.windowType == windowType &&
                    (since.map { sample.sampledAt >= $0 } ?? true)
            }
            .sorted { $0.sampledAt < $1.sampledAt }
    }

    private var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: fileURL),
              let container = try? Self.decoder.decode(QuotaSeriesContainer.self, from: data) else {
            return
        }
        samples = container.samples.sorted { $0.sampledAt < $1.sampledAt }
        enforceRetentionLimit()
    }

    private func enforceRetentionLimit() {
        guard samples.count > retentionLimit else { return }
        samples = Array(samples
            .sorted { $0.sampledAt < $1.sampledAt }
            .suffix(retentionLimit))
    }

    private func persist() {
        let container = QuotaSeriesContainer(version: 1, samples: samples)
        guard let data = try? Self.encoder.encode(container) else { return }

        let fileManager = FileManager.default
        let tempURL = directory.appendingPathComponent(".\(fileName).\(UUID().uuidString).tmp")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: tempURL, options: [])
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct QuotaSeriesContainer: Codable {
    let version: Int
    var samples: [QuotaSample]
}
