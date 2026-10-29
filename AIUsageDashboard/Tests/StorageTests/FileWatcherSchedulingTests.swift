import XCTest
@testable import AIUsageDashboardCore

final class FileWatcherSchedulingTests: XCTestCase {
    private func eventually(_ check: () async -> Bool) async {
        for _ in 0..<200 {
            if await check() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Missing watcher checkpoint")
    }

    func testContinuousEventsEmitAtTenSecondsThenStartANewBatch() async {
        let scheduler = WatchScheduler()
        let watcher = FileWatcher(paths: [], sleep: { try await scheduler.sleep($0) })
        let count = WatchEventCount()
        let stream = await watcher.events
        let consumer = Task { for await _ in stream { count.increment() } }
        defer { consumer.cancel() }
        for tick in 0..<10 {
            await watcher.handleEvents()
            await eventually { await scheduler.hasDeadline(Double(tick + 2)) }
            if tick == 0 { await eventually { await scheduler.hasDeadline(10) } }
            await scheduler.advance(by: 1)
        }
        await eventually { count.read() == 1 }
        XCTAssertEqual(count.read(), 1, "continuous traffic must not starve sync past ten seconds")
        await watcher.handleEvents()
        await eventually { await scheduler.hasDeadline(12) }
        await scheduler.advance(by: 2)
        await eventually { count.read() == 2 }
        await scheduler.advance(by: 10)
        XCTAssertEqual(count.read(), 2)
        await watcher.stop()
    }

    func testStopCancelsPendingEvents() async {
        let scheduler = WatchScheduler()
        let watcher = FileWatcher(paths: [], sleep: { try await scheduler.sleep($0) })
        let count = WatchEventCount()
        let stream = await watcher.events
        let consumer = Task { for await _ in stream { count.increment() } }
        defer { consumer.cancel() }
        await watcher.handleEvents()
        await eventually { await scheduler.hasDeadline(2) }
        await watcher.stop()
        await scheduler.advance(by: 10)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(count.read(), 0)
    }

    func testRootReorderingDoesNotCancelPendingEvents() async {
        let scheduler = WatchScheduler()
        let first = URL(fileURLWithPath: "/tmp/tokei-watch-first")
        let second = URL(fileURLWithPath: "/tmp/tokei-watch-second")
        let roots = ReorderingWatchRoots([first, second])
        let watcher = FileWatcher(sleep: { try await scheduler.sleep($0) }, pathsProvider: roots.read)
        let count = WatchEventCount()
        let stream = await watcher.events
        let consumer = Task { for await _ in stream { count.increment() } }
        defer { consumer.cancel() }
        await watcher.handleEvents()
        await eventually { await scheduler.hasDeadline(2) }
        roots.set([second, first])
        await watcher.refreshWatchPaths()
        await scheduler.advance(by: 2)
        await eventually { count.read() == 1 }
        XCTAssertEqual(count.read(), 1)
        await watcher.stop()
    }
}

private final class ReorderingWatchRoots: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [URL]
    init(_ paths: [URL]) { self.paths = paths }
    func read() -> [URL] { lock.withLock { paths } }
    func set(_ paths: [URL]) { lock.withLock { self.paths = paths } }
}

private final class WatchEventCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func read() -> Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private actor WatchScheduler {
    private struct Wait {
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }
    private var instant: TimeInterval = 0
    private var waits: [UUID: Wait] = [:]

    func hasDeadline(_ value: TimeInterval) -> Bool { waits.values.contains { $0.deadline == value } }

    func sleep(_ duration: TimeInterval) async throws {
        let identifier = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waits[identifier] = Wait(deadline: instant + duration, continuation: continuation)
            }
        }, onCancel: {
            Task { await self.cancel(identifier) }
        })
    }

    private func cancel(_ identifier: UUID) {
        waits.removeValue(forKey: identifier)?.continuation.resume(throwing: CancellationError())
    }

    func advance(by interval: TimeInterval) {
        instant += interval
        for identifier in Array(waits.keys) where waits[identifier]!.deadline <= instant {
            waits.removeValue(forKey: identifier)?.continuation.resume()
        }
    }
}
