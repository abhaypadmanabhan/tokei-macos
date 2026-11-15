import SQLite3
import XCTest
@testable import AIUsageDashboardCore

final class RefreshCacheTests: XCTestCase {
    func testAntigravityStateAliasRemainsRejectedLikeDev() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("state.vscdb")
        let alias = root.appendingPathComponent("alias.vscdb")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(target.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ItemTable (key TEXT, value BLOB)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let state = await AntigravityStateDBParser().parse(stateDatabaseURL: alias)
        XCTAssertTrue(state.warnings.contains { $0.message.contains("could not be read") },
                      "the state parser must preserve dev's NOFOLLOW boundary")
    }

    func testWALDisappearingBetweenDiscoveryAndStatIsTreatedAsAbsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("state.vscdb")
        let wal = URL(fileURLWithPath: database.path + "-wal")
        try Data("database fingerprint fixture".utf8).write(to: database)
        try Data("wal fingerprint fixture".utf8).write(to: wal)
        let fingerprint = try SQLiteSidecarCopy.fingerprint(database, readFile: { url in
            if url.lastPathComponent.hasSuffix("-wal") { try FileManager.default.removeItem(at: url) }
            return try LocalUsageFileFingerprint.read(url)
        })
        XCTAssertNil(fingerprint.wal, "a WAL removed by SQLite's last close is no longer part of the fingerprint")
    }

    func testClineSymlinkKeepsItsPreviouslySupportedNumbers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.messages.json")
        let link = root.appendingPathComponent("link.messages.json")
        try Data(ClineFixtures.cacheSession.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let parser = ClineMessagesParser()
        let parsed = await parser.parse(logSources: [.init(providerID: .cline, url: link)])
        XCTAssertEqual(parsed.lifetime.inputTokens, 7)
    }

    func testClineReadsUnchangedFileOnceAndInvalidatesOnRewriteAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.messages.json")
        let data = Data(ClineFixtures.cacheSession.utf8)
        try data.write(to: file)
        let reads = CacheReadCount()
        let parser = ClineMessagesParser(readFile: { url, limit in
            reads.increment()
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: limit) ?? Data()
        })
        let source = LogSource(providerID: .cline, url: file)
        _ = await parser.parse(logSources: [source])
        let second = await parser.parse(logSources: [source])
        XCTAssertEqual(reads.count, 1, "unchanged Cline bytes must not be read twice")
        XCTAssertEqual(second.lifetime.inputTokens, 7)
        // An atomic replacement of the same length invalidates even if mtime is restored.
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]
        try Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: ":7", with: ":9").utf8)
            .write(to: file, options: .atomic)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
        let rewritten = await parser.parse(logSources: [source])
        XCTAssertEqual(rewritten.lifetime.inputTokens, 9)
        XCTAssertEqual(reads.count, 2)
        _ = await parser.parse(logSources: [])
        try data.write(to: file)
        let restored = await parser.parse(logSources: [source])
        XCTAssertEqual(restored.lifetime.inputTokens, 7)
        XCTAssertEqual(reads.count, 3)
    }

    func testAntigravityStateSkipsUnchangedSnapshotButCopiesCommittedWAL() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("state.vscdb")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE ItemTable (key TEXT, value BLOB);", nil, nil, nil), SQLITE_OK)
        let copies = CacheReadCount()
        let parser = AntigravityStateDBParser(copyDatabase: { source, destination in
            copies.increment()
            try SQLiteSidecarCopy.copyDatabase(from: source, to: destination, using: .default)
        })
        _ = await parser.parse(stateDatabaseURL: file)
        _ = await parser.parse(stateDatabaseURL: file)
        XCTAssertEqual(copies.count, 1, "unchanged SQLite state must not be copied twice")
        let mainBefore = try Data(contentsOf: file)
        XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ItemTable VALUES ('unrelated', 'new committed value')", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(try Data(contentsOf: file), mainBefore, "the test must change only the WAL")
        _ = await parser.parse(stateDatabaseURL: file)
        XCTAssertEqual(copies.count, 2)
        _ = await parser.parse(stateDatabaseURL: file)
        XCTAssertEqual(copies.count, 2)
    }
}

private final class CacheReadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
