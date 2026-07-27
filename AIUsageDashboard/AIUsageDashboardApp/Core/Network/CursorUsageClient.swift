import Foundation
import os

/// Reads Cursor's web dashboard usage. Both calls authenticate with the WorkOS
/// session cookie (`CursorSession`) — never a Bearer token — matching the paths
/// the Cursor dashboard itself uses:
/// - tokens: `GET cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens`
///   → a per-event CSV (real input / cache / output split + cost + timestamp).
/// - quota:  `GET cursor.com/api/usage-summary` → plan utilisation %.
///
/// The client is a thin transport: it returns the raw payloads so the pure parsers
/// (`CursorUsageCSV`, `CursorUsageSummary` in `CursorUsageParsing.swift`) stay trivially
/// testable.
public protocol CursorUsageClient: Sendable {
    /// Raw CSV body of the token-usage export.
    func fetchUsageEventsCSV(cookie: String) async throws -> String
    /// Raw JSON body of the usage summary.
    func fetchUsageSummary(cookie: String) async throws -> Data
}

public enum CursorUsageError: LocalizedError, Sendable {
    case unexpectedResponse
    case httpStatus(Int)
    case cooldownActive
    case rateLimited(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "Cursor usage returned an unexpected response."
        case .httpStatus(let statusCode):
            "Cursor usage returned HTTP \(statusCode)."
        case .cooldownActive:
            "Cursor usage is cooling down after a rate limit."
        case .rateLimited:
            "Cursor usage is rate limited."
        }
    }
}

public actor CursorUsageClientImpl: CursorUsageClient {
    private let urlSession: URLSession
    private let explicitCooldownURL: URL?
    private let storageDirectory: URL
    private let legacyCooldownStore: CooldownStore?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(
        urlSession: URLSession = .shared,
        cooldownURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            guard interval > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.init(
            urlSession: urlSession,
            explicitCooldownURL: cooldownURL,
            storageDirectory: nil,
            now: now,
            sleep: sleep
        )
    }

    internal init(
        urlSession: URLSession,
        explicitCooldownURL: URL?,
        storageDirectory: URL?,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.urlSession = urlSession
        self.explicitCooldownURL = explicitCooldownURL
        let directory = storageDirectory ?? Self.defaultStorageDirectory()
        self.storageDirectory = directory
        self.legacyCooldownStore = explicitCooldownURL == nil
            ? CooldownStore(
                cooldownURL: directory.appendingPathComponent("cursor-usage-cooldown.json"),
                now: now
            )
            : nil
        self.now = now
        self.sleep = sleep
    }

    public func fetchUsageEventsCSV(cookie: String) async throws -> String {
        let data = try await get(Self.usageEventsCSVURL, cookie: cookie, accept: "text/csv, */*")
        guard let text = String(data: data, encoding: .utf8) else {
            throw CursorUsageError.unexpectedResponse
        }
        return text
    }

    public func fetchUsageSummary(cookie: String) async throws -> Data {
        try await get(Self.usageSummaryURL, cookie: cookie, accept: "application/json")
    }

    private func get(_ url: URL, cookie: String, accept: String) async throws -> Data {
        let referenceDate = now()
        if isCooldownActive(for: cookie, at: referenceDate) {
            throw CursorUsageError.cooldownActive
        }

        var lastRetryAfter: TimeInterval?
        for attempt in 1...Self.maxAttempts {
            var request = URLRequest(url: url)
            // Send our explicit Cookie header verbatim; don't let URLSession's cookie
            // storage override or strip it.
            request.httpShouldHandleCookies = false
            // SECURITY: the session cookie leaves the process only as this header, over TLS.
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.setValue("https://www.cursor.com/settings", forHTTPHeaderField: "Referer")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(accept, forHTTPHeaderField: "Accept")

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CursorUsageError.unexpectedResponse
            }

            // SECURITY: every log line below carries status codes and intervals only —
            // never the cookie, and never a response body (which can echo account data).
            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401:
                Self.logger.warning("usage rejected our session cookie (401)")
                throw CursorUsageError.httpStatus(httpResponse.statusCode)
            case 429:
                let cooldownStore = self.cooldownStore(for: cookie)
                let retryAfter = cooldownStore.retryAfter(from: httpResponse)
                lastRetryAfter = retryAfter
                let detail = "retry-after \(retryAfter.map { String(Int($0)) } ?? "unset")s, attempt \(attempt)"
                Self.logger.warning("usage rate limited (429), \(detail, privacy: .public)")
                switch UsageClientPolicy.rateLimitAction(
                    retryAfter: retryAfter,
                    attempt: attempt,
                    maxAttempts: Self.maxAttempts,
                    defaultCooldownInterval: cooldownStore.defaultCooldownInterval
                ) {
                case .sleepThenRetry(let interval):
                    await sleep(interval)
                case .giveUp(let retryAfter):
                    cooldownStore.record(duration: retryAfter)
                    throw CursorUsageError.rateLimited(retryAfter: retryAfter)
                }
            default:
                Self.logger.warning("usage returned HTTP \(httpResponse.statusCode, privacy: .public)")
                throw CursorUsageError.httpStatus(httpResponse.statusCode)
            }
        }

        // Unreachable: on the final attempt the policy returns `.giveUp`, which records the
        // cooldown and throws inside the loop. Kept because the compiler can't prove that.
        cooldownStore(for: cookie).record(duration: lastRetryAfter)
        throw CursorUsageError.rateLimited(retryAfter: lastRetryAfter)
    }

    private func cooldownStore(for cookie: String) -> CooldownStore {
        let url = explicitCooldownURL ?? perCookieCooldownURL(for: cookie)
        return CooldownStore(cooldownURL: url, now: now)
    }

    private func perCookieCooldownURL(for cookie: String) -> URL {
        // Hash the durable account id (userId), not the full cookie/JWT — a refreshed
        // token for the same account must hit the same cooldown file. identityHash
        // is the same SHA-256 prefix CursorSession uses for per-account file suffixes.
        let hash = CursorSession.identityHash(for: Self.durableAccountIdentity(for: cookie))
        return storageDirectory.appendingPathComponent("cursor-usage-cooldown-\(hash).json")
    }

    /// Extracts the stable account key from a WorkOS session cookie.
    /// Shape: `WorkosCursorSessionToken=<userId>%3A%3A<jwt>` — only `<userId>` is
    /// durable across token refresh. Falls back to the full string when the shape
    /// is unrecognised so malformed inputs still get a stable per-value key.
    /// The returned value is hashed before touching disk; never logged raw.
    private static func durableAccountIdentity(for cookie: String) -> String {
        let prefix = "WorkosCursorSessionToken="
        guard cookie.hasPrefix(prefix) else { return cookie }
        let value = cookie.dropFirst(prefix.count)
        guard let separator = value.range(of: "%3A%3A") else { return cookie }
        let userID = String(value[..<separator.lowerBound])
        return userID.isEmpty ? cookie : userID
    }

    private func isCooldownActive(for cookie: String, at referenceDate: Date) -> Bool {
        if cooldownStore(for: cookie).isActive(at: referenceDate) {
            return true
        }
        // Migration: an existing global cooldown file (pre-per-cookie schema) is
        // honored for its remaining duration, then removed. New cooldowns are
        // written per-cookie, so this fallback eventually disappears.
        guard let legacy = legacyCooldownStore else { return false }
        if legacy.isActive(at: referenceDate) {
            return true
        }
        // Once the legacy cooldown has elapsed, clean it up so it never becomes
        // a permanently stuck file.
        cleanupExpiredLegacyCooldownIfNeeded()
        return false
    }

    private func cleanupExpiredLegacyCooldownIfNeeded() {
        guard let legacy = legacyCooldownStore else { return }
        legacy.remove()
    }

    private static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AIUsageDashboard", isDirectory: true)
    }

    private static func defaultStorageURL(filename: String) -> URL {
        defaultStorageDirectory().appendingPathComponent(filename)
    }

    private static let usageEventsCSVURL = URL(
        string: "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens"
    )!
    private static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    // A desktop browser UA — the dashboard endpoints reject an empty/curl agent.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private static let logger = Logger(subsystem: "ai.padzy.tokei", category: "CursorUsageClient")
    private static let maxAttempts = 3
}
