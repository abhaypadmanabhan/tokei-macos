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
            try await Task.detached(priority: .utility) {
                try Self.runProcess(binary: binary, root: root)
            }.value
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
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = binary
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = root.path
        // Node-backed installations need their sibling node when launched from Finder.
        environment["PATH"] = binary.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let deadline = ProcessInfo.processInfo.systemUptime + min(5, max(0, timeout))
        try process.run()
        defer {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
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
        return try JSONSerialization.data(withJSONObject: reader.response(id: 2))
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
                  let type = windowType(minutes: minutes) else { continue }
            let percent = min(100, max(0, used))
            windows.append(QuotaWindow(
                providerID: .codex, type: type, used: percent, limit: 100, remaining: 100 - percent,
                resetAt: number(window["resetsAt"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
                confidence: .providerReported, source: source, observedAt: observedAt,
                windowDuration: minutes * 60
            ))
        }
        if let credits = limits["credits"] as? [String: Any], let balance = number(credits["balance"]), balance >= 0 {
            windows.append(QuotaWindow(
                providerID: .codex, type: .credits, remaining: balance,
                confidence: .providerReported, source: source, label: "Purchasable credits",
                bucketKey: "credits", observedAt: observedAt
            ))
        }
        if let credits = result["rateLimitResetCredits"] as? [String: Any],
           let count = number(credits["availableCount"]), count >= 0 {
            windows.append(QuotaWindow(
                providerID: .codex, type: .credits, remaining: count,
                confidence: .providerReported, source: source, label: "Reset bank",
                bucketKey: "reset_bank", observedAt: observedAt
            ))
        }
        return Reading(accountID: accountID, windows: windows)
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
