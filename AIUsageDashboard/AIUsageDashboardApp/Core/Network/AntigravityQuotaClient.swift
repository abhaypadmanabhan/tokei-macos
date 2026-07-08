import Foundation

public protocol AntigravityQuotaClient: Sendable {
    func fetchQuotaWindows() async throws -> [QuotaWindow]
}

public protocol AntigravityQuotaEndpointDiscovering: Sendable {
    func discoverEndpoint() async -> AntigravityQuotaEndpoint?
}

public struct AntigravityQuotaEndpoint: CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    let csrfToken: String
    public let listenPorts: [Int]

    public init(csrfToken: String, listenPorts: [Int]) {
        self.csrfToken = csrfToken
        self.listenPorts = Array(Set(listenPorts)).sorted()
    }

    public var description: String {
        "AntigravityQuotaEndpoint(listenPorts: \(listenPorts))"
    }

    public var debugDescription: String {
        description
    }
}

public enum AntigravityQuotaError: LocalizedError, Sendable {
    case discoveryUnavailable
    case unexpectedResponse
    case httpStatus(Int)
    case unrecognizedResponse

    public var errorDescription: String? {
        switch self {
        case .discoveryUnavailable:
            "Antigravity local quota endpoint could not be discovered."
        case .unexpectedResponse:
            "Antigravity local quota endpoint returned an unexpected response."
        case .httpStatus(let statusCode):
            "Antigravity local quota endpoint returned HTTP \(statusCode)."
        case .unrecognizedResponse:
            "Antigravity local quota response shape was unrecognized."
        }
    }
}

public actor AntigravityQuotaClientImpl: AntigravityQuotaClient {
    private let urlSession: URLSession
    private let discoverer: AntigravityQuotaEndpointDiscovering

    public init(
        urlSession: URLSession? = nil,
        discoverer: AntigravityQuotaEndpointDiscovering = DefaultAntigravityQuotaEndpointDiscoverer()
    ) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            self.urlSession = URLSession(
                configuration: configuration,
                delegate: LocalhostOnlyTLSDelegate(),
                delegateQueue: nil
            )
        }
        self.discoverer = discoverer
    }

    public func fetchQuotaWindows() async throws -> [QuotaWindow] {
        guard let endpoint = await discoverer.discoverEndpoint(), !endpoint.listenPorts.isEmpty else {
            throw AntigravityQuotaError.discoveryUnavailable
        }

        var lastError: Error?
        for port in endpoint.listenPorts {
            do {
                return try await fetchQuotaWindows(port: port, csrfToken: endpoint.csrfToken)
            } catch {
                lastError = error
            }
        }

        // `lastError` is always set: the guard above ensures `listenPorts` is non-empty,
        // so the loop runs at least once and every iteration either returns or records an error.
        throw lastError ?? AntigravityQuotaError.discoveryUnavailable
    }

    private func fetchQuotaWindows(port: Int, csrfToken: String) async throws -> [QuotaWindow] {
        var request = URLRequest(url: Self.endpointURL(port: port))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AntigravityQuotaError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AntigravityQuotaError.httpStatus(httpResponse.statusCode)
        }
        return try Self.decodeQuotaWindows(data, providerID: .antigravity)
    }

    static func decodeQuotaWindows(_ data: Data, providerID: ProviderID) throws -> [QuotaWindow] {
        let payload = try JSONDecoder().decode(QuotaSummaryPayload.self, from: data)

        let windows = payload.response.groups.flatMap { group in
            group.buckets.compactMap { bucket -> QuotaWindow? in
                guard let type = quotaWindowType(from: bucket.window),
                      let resetAt = JSONLDateParsing.standard.date(from: bucket.resetTime) else {
                    return nil
                }

                let remainingFraction = min(1, max(0, bucket.remainingFraction))
                return QuotaWindow(
                    providerID: providerID,
                    type: type,
                    used: round((1 - remainingFraction) * 100),
                    limit: 100,
                    remaining: round(remainingFraction * 100),
                    resetAt: resetAt,
                    confidence: .providerReported,
                    source: "antigravity-local-rpc",
                    label: group.displayName,
                    bucketKey: bucket.bucketId
                )
            }
        }

        guard !windows.isEmpty else {
            throw AntigravityQuotaError.unrecognizedResponse
        }
        return windows
    }

    private static func quotaWindowType(from value: String) -> QuotaWindowType? {
        switch value {
        case "weekly":
            return .weekly
        case "5h":
            return .fiveHour
        default:
            return nil
        }
    }

    private static func endpointURL(port: Int) -> URL {
        URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")!
    }
}

public struct DefaultAntigravityQuotaEndpointDiscoverer: AntigravityQuotaEndpointDiscovering {
    public init() {}

    public func discoverEndpoint() async -> AntigravityQuotaEndpoint? {
        guard let process = languageServerProcess(),
              let csrfToken = csrfToken(from: process.command),
              !csrfToken.isEmpty else {
            return nil
        }

        let ports = listenPorts(pid: process.pid)
        guard !ports.isEmpty else { return nil }
        return AntigravityQuotaEndpoint(csrfToken: csrfToken, listenPorts: ports)
    }

    private func languageServerProcess() -> (pid: Int32, command: String)? {
        guard let output = run(URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "pid=,command="]) else {
            return nil
        }

        for line in output.split(separator: "\n") {
            // Filter on the Substring first; only the matching line (of hundreds) is trimmed.
            guard line.contains("language_server"), line.contains("--standalone") else {
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            return (pid, parts[1])
        }

        return nil
    }

    private func csrfToken(from command: String) -> String? {
        let arguments = command.split(separator: " ").map(String.init)
        for (index, argument) in arguments.enumerated() {
            if argument == Self.csrfTokenFlag, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix(Self.csrfTokenEqualsPrefix) {
                return String(argument.dropFirst(Self.csrfTokenEqualsPrefix.count))
            }
        }
        return nil
    }

    private func listenPorts(pid: Int32) -> [Int] {
        guard let output = run(
            URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"]
        ) else {
            return []
        }

        let pattern = #":(\d+)\s+\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return output.split(separator: "\n").compactMap { line -> Int? in
            let string = String(line)
            guard string.contains("TCP") else { return nil }
            let range = NSRange(string.startIndex..<string.endIndex, in: string)
            guard let match = regex.firstMatch(in: string, range: range),
                  let portRange = Range(match.range(at: 1), in: string) else {
                return nil
            }
            return Int(string[portRange])
        }
    }

    func run(_ executableURL: URL, arguments: [String], timeout: TimeInterval = 5) -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        // Defense-in-depth: terminate a stuck subprocess so it can never block the
        // sync (which awaits every provider). Belt to the read-ordering suspenders below.
        let watchdog = DispatchWorkItem { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Drain stdout to EOF BEFORE waiting for exit. `ps -axo command=` can emit well
        // over the ~64KB pipe buffer; if we waitUntilExit() first, the child blocks writing
        // to a full pipe while we block waiting for it — a permanent deadlock. Reading to
        // EOF consumes output as it is produced, so the child can always make progress.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let csrfTokenFlag = ["--csrf", "_", "token"].joined()
    private static let csrfTokenEqualsPrefix = csrfTokenFlag + "="
}

private struct QuotaSummaryPayload: Decodable {
    let response: QuotaSummaryResponse
}

private struct QuotaSummaryResponse: Decodable {
    let groups: [QuotaSummaryGroup]
}

private struct QuotaSummaryGroup: Decodable {
    let displayName: String
    let buckets: [QuotaSummaryBucket]
}

private struct QuotaSummaryBucket: Decodable {
    let bucketId: String
    let window: String
    let remainingFraction: Double
    let resetTime: String
}

private final class LocalhostOnlyTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.host == "127.0.0.1",
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
