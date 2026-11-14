import Foundation
import os

public actor BurnStateStore {
    public static let shared = BurnStateStore()
    private static let logger = Logger(subsystem: "ai.padzy.tokei", category: "BurnStateStore")
    private let fileURL: URL
    private var loaded: BurnState?
    private var lastWrittenData: Data?
    private var quarantineFailed = false

    public init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = (directory ?? support.appendingPathComponent("AIUsageDashboard", isDirectory: true))
            .appendingPathComponent("burn-state.json")
    }

    public func load() -> BurnState {
        if let loaded { return loaded }
        let fresh = BurnState()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { loaded = fresh; return fresh }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try Self.decoder.decode(BurnState.self, from: data)
            guard state.version == BurnState.currentVersion, state.longestStreak >= 0,
                  state.records.values.allSatisfy({ $0.value.isFinite && $0.value >= 0 }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            loaded = state
            lastWrittenData = data
            return state
        } catch {
            // Preserve bad bytes for recovery. Never overwrite an existing quarantine.
            var quarantine = fileURL.appendingPathExtension("corrupt")
            if FileManager.default.fileExists(atPath: quarantine.path) {
                quarantine = fileURL.appendingPathExtension("\(UUID().uuidString).corrupt")
            }
            do { try FileManager.default.moveItem(at: fileURL, to: quarantine) } catch {
                quarantineFailed = true
                Self.logger.error("Could not preserve unreadable burn state; writes paused.")
            }
            loaded = fresh
            return fresh
        }
    }

    /// Returns true only for a successful changed-byte write. Failed writes can retry.
    @discardableResult
    public func save(_ state: BurnState) throws -> Bool {
        _ = load()
        guard !quarantineFailed else { throw CocoaError(.fileWriteNoPermission) }
        guard state.version == BurnState.currentVersion else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try Self.encoder.encode(state)
        guard data != lastWrittenData else { return false }
        try SecureFileWriter.write(data, to: fileURL)
        loaded = state
        lastWrittenData = data
        return true
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
