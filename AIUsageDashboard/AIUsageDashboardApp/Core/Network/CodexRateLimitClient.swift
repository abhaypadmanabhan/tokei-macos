import Darwin
import Foundation

/// A short-lived stdio probe. Authentication remains entirely inside the installed CLI.
public struct CodexRateLimitClient: Sendable {
    public struct Reading: Sendable {
        public let accountID: String
        public let windows: [QuotaWindow]

        public init(accountID: String, windows: [QuotaWindow]) {
            self.accountID = accountID
            self.windows = windows
        }
    }

    enum ProbeError: Error, Equatable {
        case missingBinary, timeout, oversizedOutput, invalidResponse, processExited
    }

    public typealias Runner = @Sendable (URL, URL) async throws -> Data
    private let resolve: @Sendable () -> URL?
    private let run: Runner
    private let now: @Sendable () -> Date
    static let maximumOutputBytes = 1024 * 1024

    public init(
        resolveBinary: (@Sendable () -> URL?)? = nil,
        run: Runner? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.resolve = resolveBinary ?? { Self.resolveBinary() }
        self.run = run ?? { binary, root in
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try Self.runProcess(binary: binary, root: root) })
                }
            }
        }
        self.now = now
    }

    public func fetch(root: URL) async throws -> Reading {
        guard let binary = resolve() else { throw ProbeError.missingBinary }
        return try Self.decode(await run(binary, root), observedAt: now())
    }

    static func resolveBinary(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemPaths: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) -> URL? {
        let manager = FileManager.default
        // Prefer the user's CLI over a stale global installation. Finder's PATH
        // often hides fnm/nvm; resolving known directories avoids a login shell.
        var directories = [".local/bin", ".npm-global/bin", ".bun/bin"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
        for (path, suffix) in [
            (".local/share/fnm/node-versions", "installation/bin"),
            (".nvm/versions/node", "bin")
        ] {
            let versions = (try? manager.contentsOfDirectory(
                at: home.appendingPathComponent(path), includingPropertiesForKeys: nil
            )) ?? []
            directories += versions.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }.map { $0.appendingPathComponent(suffix, isDirectory: true) }
        }
        directories += systemPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return directories.map { $0.appendingPathComponent("codex") }
            .first { manager.isExecutableFile(atPath: $0.path) }
    }

    // POSIX poll/read, like MCPFrameReader: never block on a partial newline or let a
    // noisy child grow the buffer without a bound. One deadline covers the handshake too.
    static func runProcess(binary: URL, root: URL, timeout: TimeInterval = 5) throws -> Data {
        let input = Pipe()
        let output = Pipe()
        defer {
            try? input.fileHandleForReading.close()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        // A dead CLI must produce a write error, never a process-wide SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + min(5, max(0, timeout))
        let pid = try spawn(binary: binary, root: root, input: input, output: output)
        defer {
            // Kill even if the wrapper already exited: its descendants still own this group.
            Darwin.kill(-pid, SIGKILL)
            // And the child itself, in case it left the group (setsid): waitpid would block.
            Darwin.kill(pid, SIGKILL)
            while waitpid(pid, nil, 0) == -1 && errno == EINTR {}
        }
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9.0"
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "tokei", "title": "Tokei", "version": version]
        ]])
        var reader = ResponseReader(descriptor: output.fileHandleForReading.fileDescriptor, deadline: deadline)
        _ = try reader.response(id: 1)
        try send(["jsonrpc": "2.0", "method": "initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": NSNull()])
        let result = try reader.response(id: 2)
        // Re-serialising a non-finite number raises an Objective-C exception, which would
        // abort Tokei: a broken or planted `codex` must fail the probe, not the app.
        guard JSONSerialization.isValidJSONObject(result) else { throw ProbeError.invalidResponse }
        return try JSONSerialization.data(withJSONObject: result)
    }

    /// Set the group atomically at spawn; setpgid after Process.run races exec.
    private static func spawn(binary: URL, root: URL, input: Pipe, output: Pipe) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = root.path
        // Node-backed installations need their sibling node when launched from Finder.
        environment["PATH"] = binary.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        let arguments = [binary.path, "app-server"].map { strdup($0) } + [nil]
        let variables = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            arguments.forEach { free($0) }
            variables.forEach { free($0) }
        }
        var pid: pid_t = 0
        let result = arguments.withUnsafeBufferPointer { argv in
            variables.withUnsafeBufferPointer { env in
                guard let argvBase = argv.baseAddress, let envBase = env.baseAddress else { return EINVAL }
                return posix_spawn(&pid, binary.path, &actions, &attributes, argvBase, envBase)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        return pid
    }

    private struct ResponseReader {
        let descriptor: Int32
        let deadline: TimeInterval
        private var buffer = Data()
        private var totalBytes = 0

        init(descriptor: Int32, deadline: TimeInterval) {
            self.descriptor = descriptor
            self.deadline = deadline
        }

        mutating func response(id: Int) throws -> [String: Any] {
            while true {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw ProbeError.timeout }
                guard let newline = buffer.firstIndex(of: 0x0A) else {
                    try readChunk()
                    continue
                }
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      message["id"] as? Int == id else { continue }
                guard let result = message["result"] as? [String: Any] else { throw ProbeError.invalidResponse }
                return result
            }
        }

        private mutating func readChunk() throws {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ProbeError.timeout }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pollDescriptor, 1, Int32(min(100, ceil(remaining * 1000))))
            if ready < 0 {
                if errno == EINTR { return }
                throw ProbeError.processExited
            }
            guard ready > 0 else { return }
            var bytes = [UInt8](repeating: 0, count: 16 * 1024)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0, errno == EINTR { return }
            guard count > 0 else { throw ProbeError.processExited }
            totalBytes += count
            guard totalBytes <= maximumOutputBytes else { throw ProbeError.oversizedOutput }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }

    static func decode(_ data: Data, observedAt: Date) throws -> Reading {
        guard data.count <= maximumOutputBytes,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identity = result["accountId"] as? String, !identity.isEmpty else {
            throw ProbeError.invalidResponse
        }
        let accountID = ProviderAccountNormalizer.stableID(providerID: .codex, quotaIdentity: identity)
        let byID = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        guard let limits = byID?["codex"] ?? result["rateLimits"] as? [String: Any],
              limits["limitId"] as? String == "codex" else {
            return Reading(accountID: accountID, windows: [])
        }
        let source = "Codex app-server account/rateLimits/read"
        var windows: [QuotaWindow] = []
        for position in ["primary", "secondary"] {
            guard let window = limits[position] as? [String: Any],
                  let used = number(window["usedPercent"]),
                  let minutes = number(window["windowDurationMins"]), minutes > 0,
                  minutes <= maximumWindowMinutes,
                  let type = windowType(minutes: minutes) else { continue }
            let percent = min(100, max(0, used))
            windows.append(QuotaWindow(
                providerID: .codex, type: type, used: percent, limit: 100, remaining: 100 - percent,
                resetAt: resetDate(number(window["resetsAt"]), observedAt: observedAt),
                confidence: .providerReported, source: source, observedAt: observedAt,
                windowDuration: minutes * 60
            ))
        }
        if let credits = limits["credits"] as? [String: Any], let balance = number(credits["balance"]),
           (0...maximumCreditCount).contains(balance) {
            windows.append(QuotaWindow(
                providerID: .codex, type: .credits, remaining: balance,
                confidence: .providerReported, source: source, label: "Purchasable credits",
                bucketKey: "credits", observedAt: observedAt
            ))
        }
        if let credits = result["rateLimitResetCredits"] as? [String: Any],
           let count = number(credits["availableCount"]), (0...maximumCreditCount).contains(count) {
            windows.append(QuotaWindow(
                providerID: .codex, type: .credits, remaining: count,
                confidence: .providerReported, source: source, label: "Reset bank",
                bucketKey: "reset_bank", observedAt: observedAt
            ))
        }
        return Reading(accountID: accountID, windows: windows)
    }

    /// Credit balances and reset counts render through `Int(...)`; a value this large is a
    /// broken response, never a real balance.
    private static let maximumCreditCount: Double = 1_000_000_000

    /// No real Codex window is longer than a year; anything larger is a broken response.
    private static let maximumWindowMinutes: Double = 366 * 24 * 60

    /// A reset epoch within 400 days of the reading, else unknown: an absurd value would
    /// otherwise reach `Int(interval)` in the countdown views and trap.
    private static func resetDate(_ epoch: Double?, observedAt: Date) -> Date? {
        guard let epoch, epoch > 0 else { return nil }
        let date = Date(timeIntervalSince1970: epoch)
        return date.timeIntervalSince(observedAt) <= 400 * 86_400 ? date : nil
    }

    private static func windowType(minutes: Double) -> QuotaWindowType? {
        if minutes <= 6 * 60 { return .session }
        if minutes >= 28 * 24 * 60 { return .monthly }
        if abs(minutes - 7 * 24 * 60) <= 24 * 60 { return .weekly }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
}
