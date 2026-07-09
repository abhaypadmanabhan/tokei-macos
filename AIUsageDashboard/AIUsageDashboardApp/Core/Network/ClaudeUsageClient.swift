import Foundation

public protocol ClaudeUsageClient: Sendable {
    func fetchQuotaWindows() async throws -> [QuotaWindow]
}

public protocol ClaudeUsageCredentialsReading: Sendable {
    func readCredentials() async throws -> ClaudeUsageCredentials
}

public struct ClaudeUsageCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }
}

public enum ClaudeUsageError: LocalizedError, Sendable {
    case missingCredentials
    case expiredCredentials
    case unauthorized
    case cooldownActive
    case unexpectedResponse
    case unrecognizedResponse
    case httpStatus(Int)
    case rateLimited(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Claude usage credentials could not be found. Run `claude` once, then try again."
        case .expiredCredentials:
            "Claude usage credentials are expired. Run `claude` once, then try again."
        case .unauthorized:
            "Claude usage credentials were rejected. Run `claude` once, then try again."
        case .cooldownActive:
            "Claude usage is cooling down after a rate limit."
        case .unexpectedResponse:
            "Claude usage returned an unexpected response."
        case .unrecognizedResponse:
            "Claude usage response shape was unrecognized."
        case .httpStatus(let statusCode):
            "Claude usage returned HTTP \(statusCode)."
        case .rateLimited:
            "Claude usage is rate limited."
        }
    }
}

/// Reads a generic-password value via the `security` CLI, avoiding the GUI authorization
/// prompt that `SecItemCopyMatching` raises for keychain items owned by another process.
/// Injected so tests can simulate exit 0 + payload, non-zero exit, and timeout without
/// touching the real Keychain.
public protocol KeychainPasswordSpawning: Sendable {
    func readPassword(service: String) -> String?
}

/// Default reader: spawns `/usr/bin/security find-generic-password -s <service> -w`.
///
/// Why this replaces `SecItemCopyMatching`: the `"Claude Code-credentials"` item is owned and
/// recreated by the Claude Code CLI on every OAuth refresh. Its ACL trusts `/usr/bin/security`
/// (the context the CLI created it in), and that trust survives the CLI deleting+recreating the
/// item each rotation — unlike an in-process grant to Tokei, which macOS re-prompts for and which
/// the CLI wipes on every recreate. Spawning `security` therefore reads with no dialog.
public struct SecurityCLIKeychainReader: KeychainPasswordSpawning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    public func readPassword(service: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        // Hard timeout so a hung `security` never blocks the sync loop. The token payload is well
        // under the pipe buffer, so reading after exit cannot deadlock.
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}

public struct DefaultClaudeUsageCredentialsReader: ClaudeUsageCredentialsReading {
    private let credentialsURL: URL
    private let keychainReader: KeychainPasswordSpawning
    private static let keychainService = "Claude Code-credentials"

    public init(
        credentialsURL: URL? = nil,
        keychainReader: KeychainPasswordSpawning = SecurityCLIKeychainReader()
    ) {
        self.credentialsURL = credentialsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        self.keychainReader = keychainReader
    }

    public func readCredentials() async throws -> ClaudeUsageCredentials {
        // 1. File first — cheap, cross-platform. On macOS this file is absent (Claude Code stores
        //    credentials only in Keychain) so this is a no-op here, but it is the correct primary
        //    path on Linux/Windows and future-proofs the reader.
        if let data = try? Data(contentsOf: credentialsURL),
           let credentials = try? Self.decodeCredentials(data) {
            return credentials
        }

        // 2. macOS load-bearing read — spawn `security -w` (see SecurityCLIKeychainReader) instead
        //    of SecItemCopyMatching. No GUI prompt, survives the CLI recreating the item.
        if let raw = keychainReader.readPassword(service: Self.keychainService),
           let credentials = try? Self.decodeCredentials(Data(raw.utf8)) {
            return credentials
        }

        // 3. Calm disconnected state — no dialog storm, no retry. A single failed read is final for
        //    this cycle; the caller surfaces "Claude not connected" until the user acts / relaunches.
        throw ClaudeUsageError.missingCredentials
    }

    static func decodeCredentials(_ data: Data) throws -> ClaudeUsageCredentials {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let token = findString(in: object, keys: ["accessToken", "access_token"]) {
            return ClaudeUsageCredentials(
                accessToken: token,
                expiresAt: findExpiry(in: object)
            )
        }

        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ClaudeUsageError.missingCredentials }
        return ClaudeUsageCredentials(accessToken: token)
    }

    private static func findString(in value: Any, keys: Set<String>) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, candidate) in dictionary {
                if keys.contains(key), let string = candidate as? String, !string.isEmpty {
                    return string
                }
            }
            for candidate in dictionary.values {
                if let found = findString(in: candidate, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for candidate in array {
                if let found = findString(in: candidate, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func findExpiry(in value: Any) -> Date? {
        findDate(in: value, keys: ["expiresAt", "expires_at", "expiration", "expirationTime"])
    }

    private static func findDate(in value: Any, keys: Set<String>) -> Date? {
        if let dictionary = value as? [String: Any] {
            for (key, candidate) in dictionary where keys.contains(key) {
                if let date = date(from: candidate) { return date }
            }
            for candidate in dictionary.values {
                if let found = findDate(in: candidate, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for candidate in array {
                if let found = findDate(in: candidate, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func date(from value: Any) -> Date? {
        if let string = value as? String {
            return JSONLDateParsing.iso8601(string) ?? Double(string).map(timestampDate)
        }
        if let double = value as? Double { return timestampDate(double) }
        if let int = value as? Int { return timestampDate(Double(int)) }
        if let number = value as? NSNumber { return timestampDate(number.doubleValue) }
        return nil
    }

    private static func timestampDate(_ value: Double) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

public actor ClaudeUsageClientImpl: ClaudeUsageClient {
    private let urlSession: URLSession
    private let credentialsReader: ClaudeUsageCredentialsReading
    private let cacheURL: URL
    private let cooldownURL: URL
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(
        urlSession: URLSession = .shared,
        credentialsReader: ClaudeUsageCredentialsReading = DefaultClaudeUsageCredentialsReader(),
        cacheURL: URL? = nil,
        cooldownURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            guard interval > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.urlSession = urlSession
        self.credentialsReader = credentialsReader
        self.cacheURL = cacheURL ?? Self.defaultStorageURL(filename: "claude-usage-cache.json")
        self.cooldownURL = cooldownURL ?? Self.defaultStorageURL(filename: "claude-usage-cooldown.json")
        self.now = now
        self.sleep = sleep
    }

    public func fetchQuotaWindows() async throws -> [QuotaWindow] {
        let referenceDate = now()
        if let fresh = cachedWindows(at: referenceDate, maxAge: Self.freshCacheInterval, stale: false) {
            return fresh
        }

        if cooldownActive(at: referenceDate) {
            if let stale = cachedWindows(at: referenceDate, maxAge: Self.maxStaleInterval, stale: true) {
                return stale
            }
            throw ClaudeUsageError.cooldownActive
        }

        let credentials = try await credentialsReader.readCredentials()
        guard !credentials.isExpired(at: referenceDate) else {
            throw ClaudeUsageError.expiredCredentials
        }

        do {
            let windows = try await fetchLiveWindows(credentials: credentials)
            try persistCache(windows, fetchedAt: now())
            return windows
        } catch ClaudeUsageError.rateLimited(let retryAfter) {
            try? persistCooldown(duration: retryAfter)
            if let stale = cachedWindows(at: now(), maxAge: Self.maxStaleInterval, stale: true) {
                return stale
            }
            throw ClaudeUsageError.rateLimited(retryAfter: retryAfter)
        } catch ClaudeUsageError.unauthorized {
            throw ClaudeUsageError.unauthorized
        } catch ClaudeUsageError.expiredCredentials {
            throw ClaudeUsageError.expiredCredentials
        } catch ClaudeUsageError.missingCredentials {
            throw ClaudeUsageError.missingCredentials
        } catch {
            if let stale = cachedWindows(at: now(), maxAge: Self.maxStaleInterval, stale: true) {
                return stale
            }
            throw error
        }
    }

    public static func decodeQuotaWindows(
        _ data: Data,
        providerID: ProviderID = .claudeCode
    ) throws -> [QuotaWindow] {
        let payload = try JSONDecoder().decode(ClaudeUsagePayload.self, from: data)
        var windows = payload.limits?.compactMap { entry in
            quotaWindow(from: entry, providerID: providerID)
        } ?? []

        if windows.isEmpty {
            if let session = payload.fiveHour.flatMap({
                quotaWindow(from: $0, type: .session, providerID: providerID, bucketKey: "five_hour")
            }) {
                windows.append(session)
            }
            if let weekly = payload.sevenDay.flatMap({
                quotaWindow(from: $0, type: .weekly, providerID: providerID, bucketKey: "seven_day")
            }) {
                windows.append(weekly)
            }
        }

        guard !windows.isEmpty else {
            throw ClaudeUsageError.unrecognizedResponse
        }
        return windows
    }

    private func fetchLiveWindows(credentials: ClaudeUsageCredentials) async throws -> [QuotaWindow] {
        var lastRetryAfter: TimeInterval?

        for attempt in 1...Self.maxAttempts {
            let (data, response) = try await urlSession.data(for: request(accessToken: credentials.accessToken))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeUsageError.unexpectedResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return try Self.decodeQuotaWindows(data, providerID: .claudeCode)
            case 401:
                throw ClaudeUsageError.unauthorized
            case 429:
                let retryAfter = retryAfter(from: httpResponse)
                lastRetryAfter = retryAfter
                if attempt < Self.maxAttempts {
                    await sleep(min(retryAfter ?? Self.defaultCooldownInterval, Self.maxRetrySleepInterval))
                }
            default:
                throw ClaudeUsageError.httpStatus(httpResponse.statusCode)
            }
        }

        throw ClaudeUsageError.rateLimited(retryAfter: lastRetryAfter)
    }

    private func request(accessToken: String) -> URLRequest {
        var request = URLRequest(url: Self.endpointURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Tokei/0.2", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        if let date = Self.httpDateFormatter.date(from: value) {
            return max(0, date.timeIntervalSince(now()))
        }
        return nil
    }

    private func cachedWindows(at referenceDate: Date, maxAge: TimeInterval, stale: Bool) -> [QuotaWindow]? {
        guard let cache = try? readCache(),
              referenceDate.timeIntervalSince(cache.fetchedAt) <= maxAge else {
            return nil
        }

        let windows = cache.windows.compactMap { window -> QuotaWindow? in
            if let resetAt = window.resetAt, resetAt <= referenceDate {
                return nil
            }
            return stale ? Self.staleWindow(from: window) : window
        }
        return windows.isEmpty ? nil : windows
    }

    private func cooldownActive(at referenceDate: Date) -> Bool {
        guard let cooldown = try? readCooldown() else { return false }
        return cooldown.until > referenceDate
    }

    private func persistCache(_ windows: [QuotaWindow], fetchedAt: Date) throws {
        try createParentDirectory(for: cacheURL)
        let data = try JSONEncoder.claudeUsageEncoder.encode(CachedQuotaWindows(fetchedAt: fetchedAt, windows: windows))
        try data.write(to: cacheURL, options: .atomic)
    }

    private func readCache() throws -> CachedQuotaWindows {
        let data = try Data(contentsOf: cacheURL)
        return try JSONDecoder.claudeUsageDecoder.decode(CachedQuotaWindows.self, from: data)
    }

    private func persistCooldown(duration: TimeInterval?) throws {
        try createParentDirectory(for: cooldownURL)
        let interval = min(Self.maxCooldownInterval, max(0, duration ?? Self.defaultCooldownInterval))
        let data = try JSONEncoder.claudeUsageEncoder.encode(Cooldown(until: now().addingTimeInterval(interval)))
        try data.write(to: cooldownURL, options: .atomic)
    }

    private func readCooldown() throws -> Cooldown {
        let data = try Data(contentsOf: cooldownURL)
        return try JSONDecoder.claudeUsageDecoder.decode(Cooldown.self, from: data)
    }

    private func createParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func quotaWindow(from entry: ClaudeUsageLimitEntry, providerID: ProviderID) -> QuotaWindow? {
        guard let used = entry.percent,
              let resetAt = entry.resetsAt.flatMap(JSONLDateParsing.iso8601) else {
            return nil
        }

        let scopedLabel = entry.scope?.model?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type: QuotaWindowType
        let label: String?
        let bucketKey: String?

        if entry.group == "session" || entry.kind == "session" {
            type = .session
            label = nil
            bucketKey = entry.kind
        } else if entry.group == "weekly", let scopedLabel, !scopedLabel.isEmpty {
            type = .perModel
            label = scopedLabel
            bucketKey = "\(entry.kind):\(scopedLabel)"
        } else if entry.group == "weekly" {
            type = .weekly
            label = nil
            bucketKey = entry.kind
        } else {
            return nil
        }

        return quotaWindow(
            used: used,
            resetAt: resetAt,
            type: type,
            providerID: providerID,
            label: label,
            bucketKey: bucketKey
        )
    }

    private static func quotaWindow(
        from limit: ClaudeUsageFallbackLimit,
        type: QuotaWindowType,
        providerID: ProviderID,
        bucketKey: String
    ) -> QuotaWindow? {
        guard let used = limit.utilization,
              let resetAt = limit.resetsAt.flatMap(JSONLDateParsing.iso8601) else {
            return nil
        }
        return quotaWindow(used: used, resetAt: resetAt, type: type, providerID: providerID, bucketKey: bucketKey)
    }

    private static func quotaWindow(
        used: Double,
        resetAt: Date,
        type: QuotaWindowType,
        providerID: ProviderID,
        label: String? = nil,
        bucketKey: String? = nil
    ) -> QuotaWindow {
        let clamped = min(100, max(0, used))
        return QuotaWindow(
            providerID: providerID,
            type: type,
            used: clamped,
            limit: 100,
            remaining: max(0, 100 - clamped),
            resetAt: resetAt,
            confidence: .providerReported,
            source: source,
            label: label,
            bucketKey: bucketKey
        )
    }

    private static func staleWindow(from window: QuotaWindow) -> QuotaWindow {
        QuotaWindow(
            providerID: window.providerID,
            type: window.type,
            used: window.used,
            limit: window.limit,
            remaining: window.remaining,
            resetAt: window.resetAt,
            confidence: .estimated,
            source: window.source.contains("(stale)") ? window.source : "\(window.source) (stale)",
            label: window.label,
            bucketKey: window.bucketKey
        )
    }

    private static func defaultStorageURL(filename: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AIUsageDashboard", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private static let endpointURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let source = "api.anthropic.com/api/oauth/usage"
    private static let maxAttempts = 3
    private static let freshCacheInterval: TimeInterval = 10 * 60
    private static let maxStaleInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let defaultCooldownInterval: TimeInterval = 5 * 60
    private static let maxCooldownInterval: TimeInterval = 60 * 60
    private static let maxRetrySleepInterval: TimeInterval = 30
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

private struct ClaudeUsagePayload: Decodable {
    let fiveHour: ClaudeUsageFallbackLimit?
    let sevenDay: ClaudeUsageFallbackLimit?
    let limits: [ClaudeUsageLimitEntry]?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }
}

private struct ClaudeUsageFallbackLimit: Decodable {
    let utilization: Double?
    let resetsAt: String?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ClaudeUsageLimitEntry: Decodable {
    let kind: String
    let group: String
    let percent: Double?
    let resetsAt: String?
    let scope: ClaudeUsageScope?

    private enum CodingKeys: String, CodingKey {
        case kind
        case group
        case percent
        case resetsAt = "resets_at"
        case scope
    }
}

private struct ClaudeUsageScope: Decodable {
    let model: ClaudeUsageModelScope?
}

private struct ClaudeUsageModelScope: Decodable {
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct CachedQuotaWindows: Codable {
    let fetchedAt: Date
    let windows: [QuotaWindow]
}

private struct Cooldown: Codable {
    let until: Date
}

private extension JSONEncoder {
    static var claudeUsageEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var claudeUsageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
