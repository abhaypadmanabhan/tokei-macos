import Foundation
import os

/// Reads the SuperGrok usage pool the same way the Grok CLI's own `/usage` view does:
/// `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with the login the CLI
/// already saved in `~/.grok/auth.json` (xai-org/grok-build, `extensions/billing.rs`).
///
/// SECURITY: the login key leaves the process only as the `Authorization` header over TLS
/// to xAI's own host. Tokei never writes, refreshes or copies the CLI's login; an expired
/// login is reported, not renewed. Log lines carry status codes and intervals only — never
/// the key, the user id, or a response body (which can echo account data).
public protocol GrokBillingClient: Sendable {
    /// Raw JSON body of the credits billing config.
    func fetchBilling() async throws -> Data
}

public enum GrokBillingError: LocalizedError, Sendable, Equatable {
    /// No usable login in `~/.grok/auth.json`.
    case notSignedIn
    /// The saved login is past its expiry; the Grok CLI refreshes it on its next run.
    case loginExpired
    case unexpectedResponse
    case httpStatus(Int)
    case cooldownActive
    case rateLimited(retryAfter: TimeInterval?)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "Grok CLI isn't signed in on this Mac."
        case .loginExpired: "Grok CLI sign-in has expired."
        case .unexpectedResponse: "Grok usage returned an unexpected response."
        case .httpStatus(let status): "Grok usage returned HTTP \(status)."
        case .cooldownActive: "Grok usage is cooling down after a rate limit."
        case .rateLimited: "Grok usage is rate limited."
        }
    }
}

/// The Grok CLI login fields the billing call needs. Never logged; `description` is redacted.
struct GrokLogin: Sendable, Equatable, CustomStringConvertible {
    let key: String
    let userID: String
    let expiresAt: Date?

    var description: String { "GrokLogin(<redacted>)" }

    /// The CLI's default OAuth2 scope (`GrokComConfig::default().auth_scope()`), then any other
    /// xAI OAuth2 scope, then the pre-OIDC legacy scope. API-key and legacy web logins are
    /// skipped: the CLI itself refuses `web_login`, and a plain API key carries no plan pool.
    static let preferredScope = "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"
    static let legacyScope = "https://accounts.x.ai/sign-in"

    /// Picks the login the CLI would use from the `auth.json` body, or `nil` when none is usable.
    static func select(fromAuthStore data: Data) -> GrokLogin? {
        guard let store = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let ranked = store.keys.sorted().sorted { rank($0) < rank($1) }
        for scope in ranked where rank(scope) < Int.max {
            guard let entry = store[scope] as? [String: Any],
                  let key = entry["key"] as? String, !key.isEmpty,
                  let userID = entry["user_id"] as? String, !userID.isEmpty else { continue }
            let mode = entry["auth_mode"] as? String
            if mode == "web_login" || mode == "grok" || mode == "api_key" { continue }
            let expiresAt = (entry["expires_at"] as? String).flatMap(parseInstant)
            return GrokLogin(key: key, userID: userID, expiresAt: expiresAt)
        }
        return nil
    }

    /// chrono writes nanosecond fractions; Foundation's ISO8601 parser takes milliseconds.
    static func parseInstant(_ raw: String) -> Date? {
        let trimmed = raw.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return JSONLDateParsing.iso8601(trimmed)
    }

    private static func rank(_ scope: String) -> Int {
        if scope == preferredScope { return 0 }
        if scope.hasPrefix("https://auth.x.ai::") { return 1 }
        if scope == legacyScope { return 2 }
        if scope == "xai::api_key" { return Int.max }
        return 3
    }
}

public actor GrokBillingClientImpl: GrokBillingClient {
    private let authFileURL: URL
    private let versionFileURL: URL
    private let urlSession: URLSession
    private let cooldownStore: CooldownStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    public init(
        grokHome: URL? = nil,
        urlSession: URLSession? = nil,
        cooldownURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            guard interval > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        let home = grokHome ?? Self.defaultGrokHome()
        self.authFileURL = home.appendingPathComponent("auth.json")
        self.versionFileURL = home.appendingPathComponent("version.json")
        self.urlSession = urlSession ?? UsageHTTPSession.shared
        self.cooldownStore = CooldownStore(
            cooldownURL: cooldownURL
                ?? Self.defaultStorageDirectory().appendingPathComponent("grok-usage-cooldown.json"),
            now: now
        )
        self.now = now
        self.sleep = sleep
    }

    /// `GROK_HOME` when set (the CLI honours it), else `~/.grok`.
    static func defaultGrokHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["GROK_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok", isDirectory: true)
    }

    public func fetchBilling() async throws -> Data {
        let login = try usableLogin()
        var lastRetryAfter: TimeInterval?
        for attempt in 1...Self.maxAttempts {
            let request = makeRequest(login: login)
            let (body, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw GrokBillingError.unexpectedResponse }
            switch httpResponse.statusCode {
            case 200..<300:
                return body
            case 401, 403:
                Self.logger.warning("usage rejected the Grok login (\(httpResponse.statusCode, privacy: .public))")
                throw GrokBillingError.httpStatus(httpResponse.statusCode)
            case 429:
                let retryAfter = cooldownStore.retryAfter(from: httpResponse)
                lastRetryAfter = retryAfter
                Self.logger.warning("usage rate limited (429), attempt \(attempt, privacy: .public)")
                switch UsageClientPolicy.rateLimitAction(
                    retryAfter: retryAfter, attempt: attempt, maxAttempts: Self.maxAttempts,
                    defaultCooldownInterval: cooldownStore.defaultCooldownInterval
                ) {
                case .sleepThenRetry(let interval):
                    await sleep(interval)
                case .giveUp(let retryAfter):
                    cooldownStore.record(duration: retryAfter)
                    throw GrokBillingError.rateLimited(retryAfter: retryAfter)
                }
            default:
                Self.logger.warning("usage returned HTTP \(httpResponse.statusCode, privacy: .public)")
                throw GrokBillingError.httpStatus(httpResponse.statusCode)
            }
        }
        cooldownStore.record(duration: lastRetryAfter)
        throw GrokBillingError.rateLimited(retryAfter: lastRetryAfter)
    }

    /// The CLI's current login, or the reason no request may be sent right now.
    private func usableLogin() throws -> GrokLogin {
        guard let data = try? Data(contentsOf: authFileURL), let login = GrokLogin.select(fromAuthStore: data) else {
            throw GrokBillingError.notSignedIn
        }
        let referenceDate = now()
        if let expiresAt = login.expiresAt, expiresAt <= referenceDate { throw GrokBillingError.loginExpired }
        if cooldownStore.isActive(at: referenceDate) { throw GrokBillingError.cooldownActive }
        return login
    }

    private func makeRequest(login: GrokLogin) -> URLRequest {
        var request = URLRequest(url: Self.billingURL, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        // SECURITY: the CLI's login leaves the process only as these headers, over TLS, to xAI.
        request.setValue("Bearer \(login.key)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(login.userID, forHTTPHeaderField: "x-userid")
        request.setValue("headless", forHTTPHeaderField: "x-grok-client-mode")
        if let version = installedCLIVersion() {
            request.setValue(version, forHTTPHeaderField: "x-grok-client-version")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The installed CLI's version from `~/.grok/version.json`, sent as the CLI does.
    private func installedCLIVersion() -> String? {
        guard let data = try? Data(contentsOf: versionFileURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = json["version"] as? String,
              version.range(of: #"^[0-9A-Za-z.+-]{1,32}$"#, options: .regularExpression) != nil else { return nil }
        return version
    }

    private static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AIUsageDashboard", isDirectory: true)
    }

    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let logger = Logger(subsystem: "ai.padzy.tokei", category: "GrokBillingClient")
    private static let maxAttempts = 2
}

/// The SuperGrok pool as the credits billing config reports it. Pure; no I/O.
public struct GrokBillingSummary: Sendable, Equatable {
    /// Included credit usage, 0…100. `nil` when the config carries no usable figure.
    public let usedPercent: Double?
    public let periodType: QuotaWindowType
    public let periodStart: Date?
    public let periodEnd: Date?
    public let subscriptionTier: String?
    public let isUnifiedPool: Bool?

    /// Prefers `creditUsagePercent` / `currentPeriod`, falling back to the deprecated
    /// `used` / `monthlyLimit` cents and `billingPeriodStart/End`, as the CLI does.
    public static func decode(_ data: Data) -> GrokBillingSummary? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let config = root["config"] as? [String: Any] else { return nil }
        let period = config["currentPeriod"] as? [String: Any]
        let percent: Double?
        if let credit = number(config["creditUsagePercent"]) {
            percent = credit
        } else if let used = cents(config["used"]), let limit = cents(config["monthlyLimit"]), limit > 0 {
            percent = used / limit * 100
        } else if config["currentPeriod"] != nil || config["isUnifiedBillingUser"] != nil {
            // proto3 JSON omits zero scalars: a credits-shaped config with no percent means 0% used.
            percent = 0
        } else {
            percent = nil
        }
        let start = (period?["start"] as? String ?? config["billingPeriodStart"] as? String)
            .flatMap(GrokLogin.parseInstant)
        let end = (period?["end"] as? String ?? config["billingPeriodEnd"] as? String)
            .flatMap(GrokLogin.parseInstant)
        let type: QuotaWindowType = (period?["type"] as? String) == "USAGE_PERIOD_TYPE_WEEKLY" ? .weekly : .monthly
        return GrokBillingSummary(
            usedPercent: percent.map { min(100, max(0, $0)) },
            periodType: type, periodStart: start, periodEnd: end,
            subscriptionTier: (root["subscription_tier"] ?? root["subscriptionTier"]).flatMap { $0 as? String }
                .flatMap { $0.isEmpty ? nil : $0 },
            isUnifiedPool: config["isUnifiedBillingUser"] as? Bool
        )
    }

    /// The one shared-pool window, or none when no figure is usable (never fabricated).
    public func quotaWindows(observedAt: Date?) -> [QuotaWindow] {
        guard let usedPercent else { return [] }
        let duration = periodStart.flatMap { start in periodEnd.map { $0.timeIntervalSince(start) } }
        return [QuotaWindow(
            providerID: .grok, type: periodType, used: usedPercent, limit: 100, remaining: 100 - usedPercent,
            resetAt: periodEnd, confidence: .providerReported, source: "cli-chat-proxy.grok.com/v1/billing",
            label: SharedQuotaPool.superGrokLabel, bucketKey: SharedQuotaPool.superGrokBucketKey,
            observedAt: observedAt, windowDuration: duration.flatMap { $0 > 0 ? $0 : nil }
        )]
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, number.doubleValue.isFinite { return number.doubleValue }
        if let string = value as? String, let number = Double(string), number.isFinite { return number }
        return nil
    }

    /// A proto `Cent` is `{"val": n}`; a `$0` cent arrives as `{}`.
    private static func cents(_ value: Any?) -> Double? {
        guard let object = value as? [String: Any] else { return nil }
        return number(object["val"]) ?? 0
    }
}
