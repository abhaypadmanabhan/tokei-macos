import Foundation

/// Typed, user-actionable failures for reading the snapshot. Staleness is NOT an
/// error here — a stale snapshot reads successfully and is flagged; only a missing,
/// unreadable, or malformed file fails.
enum SnapshotReadError: Error {
    /// App never launched (or file deleted): the snapshot doesn't exist yet.
    case missing(URL)
    case unreadable(URL, underlying: Error)
    case malformed(URL, underlying: Error)

    /// A clear, non-silent message with the fix, per the issue's failure-behavior spec.
    var message: String {
        switch self {
        case let .missing(url):
            return """
            tokei: no usage snapshot found at \(url.path)
              Launch Tokei at least once so it can write the snapshot, then retry.
              (Tokei writes it after each refresh while running.)
            """
        case let .unreadable(url, underlying):
            return "tokei: could not read \(url.path): \(underlying.localizedDescription)"
        case let .malformed(url, underlying):
            return "tokei: snapshot at \(url.path) is not valid JSON: \(underlying.localizedDescription)"
        }
    }

    var exitCode: Int32 {
        switch self {
        case .missing: return 3
        case .unreadable: return 4
        case .malformed: return 5
        }
    }
}

/// Reads and decodes the public snapshot, stamping reader-side staleness. Clock is
/// injectable so staleness handling is testable.
struct SnapshotReader {
    let fileURL: URL
    let now: () -> Date

    init(
        fileURL: URL = SnapshotReader.defaultFileURL(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.now = now
    }

    /// The app-support snapshot path, unless `TOKEI_SNAPSHOT_PATH` overrides it — a
    /// hook for tests and for pointing the helper at a non-default location.
    static func defaultFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["TOKEI_SNAPSHOT_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return AgentSnapshot.defaultFileURL()
    }

    /// - Returns: the snapshot with `stale`/`ageSeconds` populated relative to `now`.
    /// - Throws: `SnapshotReadError` with a user-facing message + exit code.
    func read() throws -> AgentSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SnapshotReadError.missing(fileURL)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SnapshotReadError.unreadable(fileURL, underlying: error)
        }
        let snapshot: AgentSnapshot
        do {
            snapshot = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: data)
        } catch {
            throw SnapshotReadError.malformed(fileURL, underlying: error)
        }
        return snapshot.withStaleness(asOf: now())
    }
}
