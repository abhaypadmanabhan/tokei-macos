import Foundation
import os

/// Why an official sign-in request did not return usage. Shared by the GitHub billing and
/// OpenCode Go clients; each provider turns it into its own words.
public enum OfficialUsageError: LocalizedError, Equatable, Sendable {
    /// No credential saved (the switch is on, the field is empty).
    case missingCredential
    /// 401: the credential is missing, wrong, revoked or expired.
    case unauthorized
    /// 403: the credential is valid but not allowed. `message` is the server's own
    /// explanation when it is short and carries nothing secret-shaped.
    case forbidden(message: String?)
    case notFound
    case cooldownActive
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .missingCredential: return "No key is saved."
        case .unauthorized: return "The saved key was rejected (HTTP 401)."
        case .forbidden(let message): return message ?? "Access was refused (HTTP 403)."
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

    /// Returns the body of a 2xx response. `forbiddenMessage` extracts a displayable reason
    /// from a 403 body; it must return `nil` for anything it cannot vouch for.
    func get(
        _ url: URL,
        token: String,
        forbiddenMessage: (Data) -> String? = { _ in nil }
    ) async throws -> Data {
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
            let path = url.path
            switch http.statusCode {
            case 200..<300:
                return data
            case 401:
                logger.warning("\(path, privacy: .public) returned 401")
                throw OfficialUsageError.unauthorized
            case 404:
                logger.warning("\(path, privacy: .public) returned 404")
                throw OfficialUsageError.notFound
            case 403 where !Self.isRateLimited(http):
                logger.warning("\(path, privacy: .public) returned 403")
                throw OfficialUsageError.forbidden(message: forbiddenMessage(data))
            case 403, 429:
                // GitHub signals its primary rate limit as 403 with `x-ratelimit-remaining: 0`.
                lastRetryAfter = try await waitOutRateLimit(http, attempt: attempt)
            default:
                logger.warning("\(path, privacy: .public) returned \(http.statusCode, privacy: .public)")
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
        let retryAfter = cooldown.retryAfter(from: http) ?? Self.rateLimitReset(http, now: now())
        let path = http.url?.path ?? ""
        let wait = retryAfter.map { String(Int($0)) } ?? "unset"
        let detail = "HTTP \(http.statusCode), retry-after \(wait)s, attempt \(attempt)"
        logger.warning("\(path, privacy: .public) rate limited, \(detail, privacy: .public)")
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

    /// A server-supplied refusal reason fit to show: short, one line, and nothing that looks
    /// like a key, token or email address. Anything else reads as `nil`.
    static func displayableMessage(_ message: String?) -> String? {
        guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= 200,
              !trimmed.contains("\n"), !trimmed.contains("@"),
              trimmed.range(of: "[A-Za-z0-9_\\-]{24,}", options: .regularExpression) == nil
        else { return nil }
        return trimmed
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
