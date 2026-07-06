import Foundation

public actor FileWatcher {
    public static let shared = FileWatcher()
    public static let defaultWatchPaths: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cline/data/sessions", isDirectory: true)
    ]
    public static let defaultWatchPath: URL = defaultWatchPaths[0]

    public struct Event: Sendable, Equatable {
        public let path: String

        public init(path: String) {
            self.path = path
        }
    }

    private let watchedURLs: [URL]
    private let debounceInterval: TimeInterval
    private var stream: FSEventStreamRef?
    private var context: Unmanaged<FileWatcherContext>?
    private var debounceTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<Event>.Continuation
    private var eventStream: AsyncStream<Event>

    public init(paths: [URL] = defaultWatchPaths, debounceInterval: TimeInterval = 2.0) {
        self.watchedURLs = paths
        self.debounceInterval = debounceInterval
        var continuation: AsyncStream<Event>.Continuation!
        self.eventStream = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    public init(path: URL, debounceInterval: TimeInterval = 2.0) {
        self.init(paths: [path], debounceInterval: debounceInterval)
    }

    public var events: AsyncStream<Event> {
        eventStream
    }

    public func start() {
        guard stream == nil else { return }

        let context = FileWatcherContext { [weak self] in
            guard let self else { return }
            Task {
                await self.handleEvents()
            }
        }
        self.context = Unmanaged.passRetained(context)

        let paths = watchedURLs.map { $0.path as NSString } as CFArray
        var callbackContext = FSEventStreamContext(
            version: 0,
            info: self.context?.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileWatcherCallback,
            &callbackContext,
            paths,
            UInt64(kFSEventStreamEventIdSinceNow),
            0,
            UInt32(kFSEventStreamCreateFlagNone)
        )

        guard let stream = stream else {
            self.context?.release()
            self.context = nil
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        context?.release()
        context = nil
    }

    private func handleEvents() {
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.emitChange()
        }
    }

    private func emitChange() {
        eventContinuation.yield(Event(path: watchedURLs.first?.path ?? ""))
    }
}

private let queue = DispatchQueue(label: "ai.AIUsageDashboard.FileWatcher")

private final class FileWatcherContext: @unchecked Sendable {
    private let onEvents: @Sendable () -> Void

    init(onEvents: @escaping @Sendable () -> Void) {
        self.onEvents = onEvents
    }

    func handleEvents() {
        onEvents()
    }
}

private func fileWatcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let context = Unmanaged<FileWatcherContext>.fromOpaque(info).takeUnretainedValue()
    context.handleEvents()
}
