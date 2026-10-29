import Foundation

public actor FileWatcher {
    public static let shared = FileWatcher()
    public static var defaultWatchPaths: [URL] {
        watchPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }
    public static var defaultWatchPath: URL { defaultWatchPaths[0] }

    static func watchPaths(homeDirectory home: URL, fileManager manager: FileManager = .default) -> [URL] {
        let entries = (try? manager.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let claudeProjects = entries.filter { $0.lastPathComponent.hasPrefix(".claude-") }
            .map { $0.appendingPathComponent("projects", isDirectory: true) }
            .filter { url in
                var directory: ObjCBool = false
                return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
            }
        let gemini = home.appendingPathComponent(".gemini", isDirectory: true)
        let roots = (try? manager.contentsOfDirectory(at: gemini, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let optional = roots.filter { $0.lastPathComponent.hasPrefix("antigravity") }
            .map { $0.appendingPathComponent("conversations", isDirectory: true) } + [
                home.appendingPathComponent(".copilot/session-state", isDirectory: true)
            ]
        return [home.appendingPathComponent(".claude/projects", isDirectory: true)] + claudeProjects + [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".cline/data/sessions", isDirectory: true)
        ] + optional.filter { url in
            var directory: ObjCBool = false
            return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }.sorted { $0.path < $1.path }
    }

    public struct Event: Sendable, Equatable {
        public let path: String

        public init(path: String) {
            self.path = path
        }
    }

    private(set) var watchedURLs: [URL]
    private let pathsProvider: (@Sendable () -> [URL])?
    private let debounceInterval: TimeInterval
    private let maximumWait: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var stream: FSEventStreamRef?
    private var context: Unmanaged<FileWatcherContext>?
    private var debounceTask: Task<Void, Never>?
    private var maximumWaitTask: Task<Void, Never>?
    private var batchID: UUID?
    private var eventContinuation: AsyncStream<Event>.Continuation
    private var eventStream: AsyncStream<Event>

    public init(
        paths: [URL]? = nil, debounceInterval: TimeInterval = 2.0, maximumWait: TimeInterval = 10,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        pathsProvider: @escaping @Sendable () -> [URL] = { FileWatcher.defaultWatchPaths }
    ) {
        self.watchedURLs = (paths ?? pathsProvider()).sorted { $0.path < $1.path }
        self.pathsProvider = paths == nil ? pathsProvider : nil
        self.debounceInterval = debounceInterval
        self.maximumWait = maximumWait
        self.sleep = sleep
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
        guard stream == nil, !watchedURLs.isEmpty else { return }

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
        batchID = nil
        debounceTask?.cancel()
        debounceTask = nil
        maximumWaitTask?.cancel()
        maximumWaitTask = nil

        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        context?.release()
        context = nil
    }

    public func refreshWatchPaths() {
        guard let pathsProvider else { return }
        let paths = pathsProvider().sorted { $0.path < $1.path }
        guard paths != watchedURLs else { return }
        let wasRunning = stream != nil
        stop()
        watchedURLs = paths
        if wasRunning { start() }
    }

    func handleEvents() {
        let identifier = batchID ?? UUID()
        if batchID == nil {
            batchID = identifier
            maximumWaitTask = scheduleChange(after: maximumWait, batchID: identifier)
        }
        debounceTask?.cancel()
        debounceTask = scheduleChange(after: debounceInterval, batchID: identifier)
    }

    private func scheduleChange(after interval: TimeInterval, batchID: UUID) -> Task<Void, Never> {
        Task { [weak self, sleep] in
            do { try await sleep(interval) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.emitChange(batchID: batchID)
        }
    }

    private func emitChange(batchID: UUID) {
        guard self.batchID == batchID else { return }
        self.batchID = nil
        debounceTask?.cancel()
        debounceTask = nil
        maximumWaitTask?.cancel()
        maximumWaitTask = nil
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
