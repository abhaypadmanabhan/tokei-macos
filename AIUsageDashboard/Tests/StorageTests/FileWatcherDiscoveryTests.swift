import XCTest
@testable import AIUsageDashboardCore

final class FileWatcherDiscoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testDiscoversNewClaudeCopilotAndAntigravityRoots() throws {
        let initial = FileWatcher.watchPaths(homeDirectory: directory)
        let suffixes = [
            ".claude-account-new/projects", ".copilot/session-state",
            ".gemini/antigravity/conversations", ".gemini/antigravity-cli/conversations",
            ".gemini/other/conversations"
        ]
        for suffix in suffixes {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(suffix), withIntermediateDirectories: true
            )
        }
        let updated = FileWatcher.watchPaths(homeDirectory: directory)
        let initialPaths = Set(initial.map { $0.resolvingSymlinksInPath().path })
        let updatedPaths = Set(updated.map { $0.resolvingSymlinksInPath().path })
        for suffix in suffixes.dropLast() {
            let root = directory.appendingPathComponent(suffix).resolvingSymlinksInPath().path
            XCTAssertFalse(initialPaths.contains(root))
            XCTAssertTrue(updatedPaths.contains(root), suffix)
        }
        let unrelated = directory.appendingPathComponent(suffixes.last!).resolvingSymlinksInPath().path
        XCTAssertFalse(updatedPaths.contains(unrelated))
    }

    func testEveryRefreshReresolvesWatchPaths() async {
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        let roots = ChangingWatchRoots([first])
        let watcher = FileWatcher(pathsProvider: roots.read)
        let store = directory.appendingPathComponent("output")
        let engine = SyncEngine(
            registry: ProviderRegistry(providers: []), store: UsageStore(directory: store),
            quotaSeriesStore: QuotaSeriesStore(directory: store),
            agentSnapshotWriter: AgentSnapshotWriter(directory: store), watcher: watcher,
            evaluateThresholds: { _ in }
        )
        _ = await engine.refreshAll()
        roots.set([second])
        _ = await engine.refreshAll()
        let paths = await watcher.watchedURLs
        XCTAssertEqual(paths, [second])
        XCTAssertEqual(roots.readCount, 3, "construction plus both refreshes must resolve roots")
        await watcher.stop()
    }

    func testRootDiscoveryDoesNotReadClaudeAccountMetadata() throws {
        let projects = directory.appendingPathComponent(".claude-work/projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let manager = MetadataReadCountingManager()
        let paths = FileWatcher.watchPaths(homeDirectory: directory, fileManager: manager)
        XCTAssertTrue(paths.contains { $0.resolvingSymlinksInPath().path == projects.resolvingSymlinksInPath().path },
                      "roots=\(paths.map(\.path)); expected=\(projects.path)")
        XCTAssertEqual(manager.metadataReads, 0, "watching paths needs directory names, not account metadata")
    }
}

private final class MetadataReadCountingManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var metadataReads: Int { lock.withLock { reads } }

    override func contents(atPath path: String) -> Data? {
        lock.withLock { reads += 1 }
        return super.contents(atPath: path)
    }
}

private final class ChangingWatchRoots: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [URL]
    private var count = 0
    var readCount: Int { lock.withLock { count } }
    init(_ paths: [URL]) { self.paths = paths }
    func read() -> [URL] { lock.withLock { count += 1; return paths } }
    func set(_ paths: [URL]) { lock.withLock { self.paths = paths } }
}
