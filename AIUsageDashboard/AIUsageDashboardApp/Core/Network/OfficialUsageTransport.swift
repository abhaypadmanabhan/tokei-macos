import Foundation
import os

/// Why an official sign-in request did not return usage. Shared by the GitHub billing and
/// OpenCode Go clients; each provider turns it into its own words.
public enum OfficialUsageError: LocalizedError, Equatable, Sendable {
    /// No credential saved (the switch is on, the field is empty).
    case missingCredential
    /// 401: the credential is missing, wrong, revoked or expired.
    case unauthorized
    /// 403: access was refused. The response body may contain credentials.
    case forbidden
    case notFound
    case cooldownActive
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .missingCredential: return "No key is saved."
        case .unauthorized: return "The saved key was rejected (HTTP 401)."
        case .forbidden: return "Access was refused (HTTP 403)."
        case .notFound: return "The usage endpoint returned HTTP 404."
        case .cooldownActive: return "Cooling down after a rate limit; will retry later."
        case .rateLimited: return "Rate limited; will retry later."
        case .httpStatus(let code): return "The usage endpoint returned HTTP \(code)."
        case .unexpectedResponse: return "The usage endpoint returned an unexpected response."
        }
    }
}

/// One Bearer-authenticated GET for the official sign-in clients: honours a persisted
/// cooldown, follows `UsageClientPolicy` on 429, and maps statuses to `OfficialUsageError`.
///
/// SECURITY: the token leaves the process only as the `Authorization` header, over the
/// no-cache, same-host-redirect-only `UsageHTTPSession`. Log lines carry status codes and
/// intervals only — never the token, a header, or a response body.
struct BearerUsageTransport: Sendable {
    let urlSession: URLSession
    let cooldown: CooldownStore
    let headers: [String: String]
    let logger: Logger
    let sleep: @Sendable (TimeInterval) async -> Void
    let now: @Sendable () -> Date
    var maxAttempts = 3

    /// Returns the body of a 2xx response. Errors carry only status and retry information.
    func get(_ url: URL, token: String) async throws -> Data {
        if cooldown.isActive(at: now()) {
            throw OfficialUsageError.cooldownActive
        }
        var lastRetryAfter: TimeInterval?
        for attempt in 1...maxAttempts {
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = false
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }

            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OfficialUsageError.unexpectedResponse
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401:
                logger.warning("Usage request returned 401")
                throw OfficialUsageError.unauthorized
            case 404:
                logger.warning("Usage request returned 404")
                throw OfficialUsageError.notFound
            case 403 where !Self.isRateLimited(http):
                logger.warning("Usage request returned 403")
                throw OfficialUsageError.forbidden
            case 403, 429:
                // GitHub signals its primary rate limit as 403 with `x-ratelimit-remaining: 0`.
                lastRetryAfter = try await waitOutRateLimit(http, attempt: attempt)
            default:
                logger.warning("Usage request returned \(http.statusCode, privacy: .public)")
                throw OfficialUsageError.httpStatus(http.statusCode)
            }
        }
        // Unreachable: the final attempt's policy is `.giveUp`, which throws above.
        cooldown.record(duration: lastRetryAfter)
        throw OfficialUsageError.rateLimited(retryAfter: lastRetryAfter)
    }

    /// Sleeps and returns the `Retry-After` when the policy allows one more attempt; else
    /// records the cooldown and throws `.rateLimited`.
    private func waitOutRateLimit(_ http: HTTPURLResponse, attempt: Int) async throws -> TimeInterval? {
        let retryAfter = (cooldown.retryAfter(from: http) ?? Self.rateLimitReset(http, now: now()))
            .flatMap { $0.isFinite ? $0 : nil }
        let wait = retryAfter.map { String($0) } ?? "unset"
        let detail = "HTTP \(http.statusCode), retry-after \(wait)s, attempt \(attempt)"
        logger.warning("Usage request rate limited, \(detail, privacy: .public)")
        switch UsageClientPolicy.rateLimitAction(
            retryAfter: retryAfter,
            attempt: attempt,
            maxAttempts: maxAttempts,
            defaultCooldownInterval: cooldown.defaultCooldownInterval
        ) {
        case .sleepThenRetry(let interval):
            await sleep(interval)
            return retryAfter
        case .giveUp(let retryAfter):
            cooldown.record(duration: retryAfter)
            throw OfficialUsageError.rateLimited(retryAfter: retryAfter)
        }
    }

    private static func isRateLimited(_ response: HTTPURLResponse) -> Bool {
        response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
            || response.value(forHTTPHeaderField: "Retry-After") != nil
    }

    /// GitHub's `x-ratelimit-reset` (epoch seconds) as an interval from now.
    private static func rateLimitReset(_ response: HTTPURLResponse, now: Date) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
              let epoch = TimeInterval(raw) else { return nil }
        return max(0, epoch - now.timeIntervalSince1970)
    }

    static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AIUsageDashboard", isDirectory: true)
    }

    static let defaultSleep: @Sendable (TimeInterval) async -> Void = { interval in
        guard interval > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}
