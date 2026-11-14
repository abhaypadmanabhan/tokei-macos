import Foundation
import Darwin

public enum AgentClient: String, CaseIterable, Sendable, Identifiable {
    case claude, codex, cursor
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }
}

public struct AgentConnectionState: Sendable {
    public let client: AgentClient
    public let detected: Bool
    public let connected: Bool
    public let message: String?
}

public enum AgentConnectionError: LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

/// The app and standalone helper compile this exact file. Commands use literal argv,
/// never a shell. Only Cursor's MCP file is edited directly; CLI clients own their formats.
public struct AgentConnection: Sendable {
    public let home: URL
    public let environment: [String: String]
    public let helper: URL
    private let fallbackDirectories: [String]

    public init(helper: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                fallbackDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) {
        self.helper = helper.standardizedFileURL.resolvingSymlinksInPath()
        self.home = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory(), isDirectory: true)
        self.environment = environment
        self.fallbackDirectories = fallbackDirectories
    }

    public static var runningHelper: URL {
        if let executable = Bundle.main.executableURL { return executable.resolvingSymlinksInPath() }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    }

    public func binary(for client: AgentClient) -> URL? {
        guard client != .cursor else { return nil }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path] + fallbackDirectories
        return directories.lazy.filter { $0.hasPrefix("/") }.map {
            URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(client.rawValue)
        }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func state(for client: AgentClient) -> AgentConnectionState {
        do {
            if client == .cursor {
                let config = try cursorConfig()
                let servers = config["mcpServers"] as? [String: Any] ?? [:]
                let detected = FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor").path)
                    || FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
                return AgentConnectionState(client: client, detected: detected,
                                            connected: servers["tokei"] != nil, message: nil)
            }
            guard let binary = binary(for: client) else {
                return AgentConnectionState(client: client, detected: false, connected: false, message: nil)
            }
            if client == .codex, !FileManager.default.fileExists(atPath: codexHome.path) {
                return AgentConnectionState(client: client, detected: true, connected: false, message: nil)
            }
            let result = try run(binary, arguments: getArguments(client))
            return AgentConnectionState(client: client, detected: true, connected: result.status == 0,
                message: result.status != 0 && !isMissing(result.output)
                    ? "Could not read the connection. Open \(client.name) once, then reopen Settings." : nil)
        } catch {
            return AgentConnectionState(client: client, detected: true, connected: false,
                                        message: error.localizedDescription)
        }
    }

    /// Dry runs never execute a client or inspect a config file.
    public func change(_ client: AgentClient, install: Bool, dryRun: Bool = false) throws -> String {
        do { return try performChange(client, install: install, dryRun: dryRun) }
        catch let error as AgentConnectionError { throw error }
        catch {
            throw AgentConnectionError.failed("\(client.name) could not save its tokei connection. Check that its configuration folder is writable, then retry.")
        }
    }

    private func performChange(_ client: AgentClient, install: Bool, dryRun: Bool) throws -> String {
        if client == .cursor {
            if dryRun {
                return "Would \(install ? "register" : "remove") tokei in \(cursorURL.path)\(install ? ": \(quoted(helper.path)) mcp" : "")."
            }
            return try changeCursor(install: install)
        }
        guard let binary = binary(for: client) else {
            throw AgentConnectionError.failed("\(client.name) command was not found. Install \(client.name), then try again.")
        }
        let arguments = install
            ? ["mcp", "add"] + (client == .claude ? ["--scope", "user"] : []) + ["tokei", "--", helper.path, "mcp"]
            : ["mcp", "remove"] + (client == .claude ? ["--scope", "user"] : []) + ["tokei"]
        if dryRun { return "Would run: " + ([binary.path] + arguments).map(quoted).joined(separator: " ") }
        // Codex rejects even read-only MCP queries when CODEX_HOME does not exist.
        // Prepare an empty config directory only for an explicit install, never detection.
        if client == .codex, !FileManager.default.fileExists(atPath: codexHome.path) {
            if !install { return "Codex: tokei is already disconnected; no change." }
            try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let existing = try run(binary, arguments: getArguments(client))
        if install, existing.status == 0 {
            if matches(existing.output, client: client) { return "\(client.name): tokei is already connected; no change." }
            throw AgentConnectionError.failed("\(client.name) already has a different tokei connection. Disconnect it first, then connect again.")
        }
        if !install, existing.status != 0, isMissing(existing.output) {
            return "\(client.name): tokei is already disconnected; no change."
        }
        if existing.status != 0, !isMissing(existing.output) {
            throw AgentConnectionError.failed("\(client.name) could not read its tokei connection. Run \(client.rawValue) mcp get tokei to check it, then retry.")
        }
        let result = try run(binary, arguments: arguments)
        guard result.status == 0 else {
            throw AgentConnectionError.failed("\(client.name) did not \(install ? "connect" : "disconnect") tokei. Run \(client.rawValue) mcp --help to check your client, then retry.")
        }
        let after = try run(binary, arguments: getArguments(client))
        guard install ? (after.status == 0 && matches(after.output, client: client))
                      : (after.status != 0 && isMissing(after.output)) else {
            throw AgentConnectionError.failed("\(client.name) did not confirm the change. Check \(client.rawValue) mcp get tokei before retrying.")
        }
        return "\(client.name): \(install ? "connected" : "disconnected") tokei\(install ? " (\(helper.path) mcp)" : "")."
    }

    public func installCommand(force: Bool = false) throws -> String {
        do { return try performInstallCommand(force: force) }
        catch let error as AgentConnectionError { throw error }
        catch {
            throw AgentConnectionError.failed("The tokei command could not be installed. Check that ~/.local/bin is writable, then retry.")
        }
    }

    private func performInstallCommand(force: Bool) throws -> String {
        let directory = home.appendingPathComponent(".local/bin", isDirectory: true)
        let link = directory.appendingPathComponent("tokei")
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: helper.path) else {
            throw AgentConnectionError.failed("The bundled tokei command is missing. Reinstall Tokei, then try again.")
        }
        let attributes = try? fm.attributesOfItem(atPath: link.path)
        if attributes != nil {
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == helper.path {
                return "tokei command is already installed; no change." + pathHint(directory)
            }
            guard force, attributes?[.type] as? FileAttributeType != .typeDirectory else {
                throw AgentConnectionError.failed("\(link.path) already points elsewhere. Run tokei install --force to replace the file or link.")
            }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Rename a sibling symlink over the old entry: no interval with a missing command.
        let pending = directory.appendingPathComponent(".tokei-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: pending) }
        try fm.createSymbolicLink(atPath: pending.path, withDestinationPath: helper.path)
        guard Darwin.rename(pending.path, link.path) == 0 else {
            throw AgentConnectionError.failed("The tokei command could not be installed. Check that you can write to \(directory.path), then retry.")
        }
        return "Installed \(link.path) → \(helper.path)." + pathHint(directory)
    }

    private func pathHint(_ directory: URL) -> String {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.contains(directory.path) ? "" : "\nAdd ~/.local/bin to PATH in your shell settings: export PATH=\"$HOME/.local/bin:$PATH\""
    }

    private var codexHome: URL {
        URL(fileURLWithPath: environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path, isDirectory: true)
    }

    private var cursorURL: URL { home.appendingPathComponent(".cursor/mcp.json") }

    private func cursorConfig() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: cursorURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: cursorURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["mcpServers"] == nil || object["mcpServers"] is [String: Any] else {
            throw AgentConnectionError.failed("Cursor's mcp.json is not a valid MCP object. Fix its JSON, then retry; Tokei kept the file.")
        }
        return object
    }

    private func changeCursor(install: Bool) throws -> String {
        var config = try cursorConfig()
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        let wanted: [String: Any] = ["command": helper.path, "args": ["mcp"]]
        if install, let current = servers["tokei"] as? [String: Any],
           NSDictionary(dictionary: current).isEqual(to: wanted) {
            return "Cursor: tokei is already connected; no change."
        }
        if !install, servers["tokei"] == nil { return "Cursor: tokei is already disconnected; no change." }
        if install { servers["tokei"] = wanted } else { servers.removeValue(forKey: "tokei") }
        config["mcpServers"] = servers
        let fm = FileManager.default
        let backup = URL(fileURLWithPath: cursorURL.path + ".bak")
        if fm.fileExists(atPath: cursorURL.path), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: cursorURL, to: backup)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try fm.createDirectory(at: cursorURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: cursorURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cursorURL.path)
        return "Cursor: \(install ? "connected" : "disconnected") tokei in \(cursorURL.path)."
    }

    private func getArguments(_ client: AgentClient) -> [String] {
        ["mcp", "get", "tokei"] + (client == .codex ? ["--json"] : [])
    }

    private func matches(_ output: String, client: AgentClient) -> Bool {
        if client == .codex,
           let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
           let transport = object["transport"] as? [String: Any] {
            return transport["command"] as? String == helper.path && transport["args"] as? [String] == ["mcp"]
        }
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains("Command: \(helper.path)") && lines.contains("Args: mcp")
    }

    private func isMissing(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("no mcp server found") || lower.contains("no mcp server named")
            || lower.contains("no server named") || lower.contains("not found")
    }

    private func quoted(_ value: String) -> String {
        if value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-").contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct CommandResult { let status: Int32; let output: String }

    private func run(_ binary: URL, arguments: [String]) throws -> CommandResult {
        // A private capture file avoids pipe backpressure. Child output is only parsed,
        // never surfaced to users (client diagnostics can include sensitive config).
        let capture = FileManager.default.temporaryDirectory.appendingPathComponent("tokei-connect-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: capture.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: capture) }
        let handle = try FileHandle(forWritingTo: capture)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var env = environment
        env["HOME"] = home.path
        env["CLAUDE_CONFIG_DIR"] = env["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path
        env["CODEX_HOME"] = env["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path
        process.environment = env
        process.currentDirectoryURL = home
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { @Sendable _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 12) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut { Darwin.kill(process.processIdentifier, SIGKILL) }
            throw AgentConnectionError.failed("\(binary.lastPathComponent) took too long to respond. Open the client once, then retry.")
        }
        let readHandle = try FileHandle(forReadingFrom: capture)
        defer { try? readHandle.close() }
        let data = try readHandle.read(upToCount: 131_072) ?? Data()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
