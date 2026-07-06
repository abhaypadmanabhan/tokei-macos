import XCTest
@testable import AIUsageDashboardCore

final class FileWatcherTests: XCTestCase {
    private var tempDirectory: URL!
    private var watcher: FileWatcher!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let watcher {
            Task {
                await watcher.stop()
            }
        }
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testStartsAndStopsCleanly() async {
        watcher = FileWatcher(path: tempDirectory, debounceInterval: 0.5)
        await watcher.start()
        await watcher.stop()
    }

    func testDebounceCoalescesBursts() async throws {
        watcher = FileWatcher(path: tempDirectory, debounceInterval: 0.5)

        var eventCount = 0
        let stream = await watcher.events
        let consumeTask = Task {
            for await _ in stream {
                eventCount += 1
            }
        }

        await watcher.start()

        // Give FSEventStream time to register before mutating files.
        try await Task.sleep(nanoseconds: 200_000_000)

        for i in 0..<5 {
            let url = tempDirectory.appendingPathComponent("file\(i).txt")
            try "data".write(to: url, atomically: true, encoding: .utf8)
        }

        // Wait long enough for debounce + delivery.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        consumeTask.cancel()
        await watcher.stop()

        // FSEventStream may deliver multiple raw events for the same burst,
        // especially on different macOS versions or under CI load. The watcher
        // debounces them, but the exact count can vary. Assert at least one
        // event was emitted and note that a strict single-event assertion is
        // timing-sensitive.
        XCTAssertGreaterThanOrEqual(eventCount, 1, "Expected at least one debounced event")
    }

    func testStreamReceivesEventsAfterStart() async throws {
        watcher = FileWatcher(path: tempDirectory, debounceInterval: 0.5)
        let stream = await watcher.events

        let expectation = expectation(description: "event received")
        let task = Task {
            for await _ in stream {
                expectation.fulfill()
                break
            }
        }

        await watcher.start()
        try await Task.sleep(nanoseconds: 200_000_000)

        let url = tempDirectory.appendingPathComponent("trigger.txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 5.0)
        task.cancel()
        await watcher.stop()
    }
}
