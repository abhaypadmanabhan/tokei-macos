import Foundation

public actor FileWatcher {
    public static let shared = FileWatcher()
    public static var defaultWatchPaths: [URL] {
        watchPaths(homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                   environment: ProcessInfo.processInfo.environment)
    }
    public static var defaultWatchPath: URL { defaultWatchPaths[0] }

    static func watchPaths(homeDirectory home: URL, fileManager manager: FileManager = .default,
                           environment: [String: String] = [:]) -> [URL] {
        let entries = (try? manager.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let claudeProjects = entries.filter { $0.lastPathComponent.hasPrefix(".claude-") }
            .map { $0.appendingPathComponent("projects", isDirectory: true) }
            .filter { url in
                var directory: ObjCBool = false
                return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
            }
        let codexSessions = entries.filter { $0.lastPathComponent.hasPrefix(".codex-") }
            .map { $0.appendingPathComponent("sessions", isDirectory: true) }
            .filter { manager.fileExists(atPath: $0.path) }
        let overrides = [("CLAUDE_CONFIG_DIR", "projects"), ("CODEX_HOME", "sessions")].compactMap { key, child in
            environment[key].flatMap { value -> URL? in
                guard !value.isEmpty else { return nil }
                return URL(fileURLWithPath: value, isDirectory: true).appendingPathComponent(child, isDirectory: true)
            }
        }
        let gemini = home.appendingPathComponent(".gemini", isDirectory: true)
        let roots = (try? manager.contentsOfDirectory(at: gemini, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let optional = roots.filter { $0.lastPathComponent.hasPrefix("antigravity") }
            .map { $0.appendingPathComponent("conversations", isDirectory: true) } + [
                home.appendingPathComponent(".copilot/session-state", isDirectory: true)
            ]
        return [home.appendingPathComponent(".claude/projects", isDirectory: true)] + claudeProjects + codexSessions + overrides + [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".cline/data/sessions", isDirectory: true)
        ] + optional.filter { url in
            var directory: ObjCBool = false
            return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }.sorted { $0.path < $1.path }
    }

    public struct Event: Sendable, Equatable {
        public let path: String
        public let paths: [String]
        public let requiresFullRescan: Bool

        public init(path: String) {
            self.path = path
            self.paths = [path]
            self.requiresFullRescan = false
        }

        public init(paths: [String], requiresFullRescan: Bool = false) {
            self.paths = Array(Set(paths)).sorted()
            self.path = self.paths.first ?? ""
            self.requiresFullRescan = requiresFullRescan
        }
    }

    private(set) var watchedURLs: [URL]
    private let pathsProvider: (@Sendable () -> [URL])?
    private let debounceInterval: TimeInterval
    private let maximumWait: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let resolvePath: @Sendable (URL) -> String
    private var stream: FSEventStreamRef?
    private var context: Unmanaged<FileWatcherContext>?
    private var debounceTask: Task<Void, Never>?
    private var maximumWaitTask: Task<Void, Never>?
    private var batchID: UUID?
    private var pendingPaths: Set<String> = []
    private var pendingFullRescan = false
    private var eventContinuation: AsyncStream<Event>.Continuation
    private var eventStream: AsyncStream<Event>

    public init(
        paths: [URL]? = nil, debounceInterval: TimeInterval = 2.0, maximumWait: TimeInterval = 10,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        pathsProvider: @escaping @Sendable () -> [URL] = { FileWatcher.defaultWatchPaths },
        resolvePath: @escaping @Sendable (URL) -> String = { $0.resolvingSymlinksInPath().standardized.path }
    ) {
        self.watchedURLs = (paths ?? pathsProvider()).sorted { $0.path < $1.path }
        self.pathsProvider = paths == nil ? pathsProvider : nil
        self.debounceInterval = debounceInterval
        self.maximumWait = maximumWait
        self.sleep = sleep
        self.resolvePath = resolvePath
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

        let context = FileWatcherContext { [weak self] paths, rescan in
            guard let self else { return }
            Task {
                await self.handleEvents(paths: paths, requiresFullRescan: rescan)
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
            UInt32(kFSEventStreamCreateFlagFileEvents)
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
        pendingPaths.removeAll()
        pendingFullRescan = false

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
        flushPendingEvents()
        stop()
        watchedURLs = paths
        if wasRunning { start() }
    }

    /// Unknown roots and dropped FSEvents conservatively request a full scan. A shared
    /// ancestor event includes every matching provider; path components avoid prefix collisions.
    func affectedProviders(for event: Event) -> Set<ProviderID>? {
        guard !event.requiresFullRescan, !event.paths.isEmpty else { return nil }
        let roots = watchedURLs.map { root in
            let path = resolvePath(root)
            return (path: path, provider: Self.provider(for: root, resolvedPath: path, resolvePath: resolvePath))
        }
        var result: Set<ProviderID> = []
        for path in event.paths {
            let changed = resolvePath(URL(fileURLWithPath: path))
            var matched = false
            for root in roots {
                let watched = root.path
                if changed == watched || changed.hasPrefix(watched + "/") || watched.hasPrefix(changed + "/") {
                    guard let provider = root.provider else { return nil }
                    result.insert(provider)
                    matched = true
                }
            }
            if !matched { return nil }
        }
        return result
    }

    private static func provider(for root: URL, resolvedPath: String, resolvePath: (URL) -> String) -> ProviderID? {
        let parent = root.deletingLastPathComponent().lastPathComponent
        switch root.lastPathComponent {
        case "projects" where parent == ".claude" || parent.hasPrefix(".claude-"): return .claudeCode
        case "sessions" where parent == ".codex" || parent.hasPrefix(".codex-"): return .codex
        case "sessions" where root.path.hasSuffix("/.cline/data/sessions"): return .cline
        case "session-state" where parent == ".copilot": return .copilot
        case "conversations" where parent.hasPrefix("antigravity"): return .antigravity
        default: break
        }
        let environment = ProcessInfo.processInfo.environment
        for (key, child, provider) in [("CLAUDE_CONFIG_DIR", "projects", ProviderID.claudeCode),
                                       ("CODEX_HOME", "sessions", ProviderID.codex)] {
            if let directory = environment[key], !directory.isEmpty,
               resolvePath(URL(fileURLWithPath: directory).appendingPathComponent(child)) == resolvedPath { return provider }
        }
        return nil
    }

    func handleEvents(paths: [String]? = nil, requiresFullRescan: Bool = false) {
        pendingPaths.formUnion(paths ?? watchedURLs.map(\.path))
        pendingFullRescan = pendingFullRescan || requiresFullRescan
        let identifier = batchID ?? UUID()
        if batchID == nil {
            batchID = identifier
            maximumWaitTask = scheduleChange(after: maximumWait, batchID: identifier)
        }
        debounceTask?.cancel()
        debounceTask = scheduleChange(after: debounceInterval, batchID: identifier)
    }

    func flushPendingEvents() {
        if let batchID { emitChange(batchID: batchID) }
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
        let event = Event(paths: Array(pendingPaths), requiresFullRescan: pendingFullRescan)
        pendingPaths.removeAll()
        pendingFullRescan = false
        eventContinuation.yield(event)
    }
}

private let queue = DispatchQueue(label: "ai.AIUsageDashboard.FileWatcher")

private final class FileWatcherContext: @unchecked Sendable {
    private let onEvents: @Sendable ([String], Bool) -> Void

    init(onEvents: @escaping @Sendable ([String], Bool) -> Void) {
        self.onEvents = onEvents
    }

    func handleEvents(paths: [String], requiresFullRescan: Bool) {
        onEvents(paths, requiresFullRescan)
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
    let pointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    let paths = (0..<numEvents).map { String(cString: pointers[$0]) }
    let dropped = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                         | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
    let requiresFullRescan = (0..<numEvents).contains { eventFlags[$0] & dropped != 0 }
    context.handleEvents(paths: paths, requiresFullRescan: requiresFullRescan)
}
