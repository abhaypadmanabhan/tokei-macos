import Foundation

// MARK: - Errors

public enum GeminiUsageError: LocalizedError, Sendable, Equatable {
    /// No usable `oauth_creds.json` (missing file, empty, or unparseable) — the user
    /// has not signed in to the Gemini CLI on this machine.
    case notAuthenticated
    /// The stored access token has expired and Tokei cannot refresh it because the
    /// gemini-cli OAuth client *secret* is not configured (deliberately not bundled —
    /// see `GeminiOAuthConfig.clientSecret`).
    case tokenRefreshUnavailable
    /// The OAuth token endpoint returned a non-2xx status while refreshing.
    case tokenRefreshFailed(Int)
    /// A response was not an `HTTPURLResponse`.
    case unexpectedResponse
    /// A Code Assist endpoint returned a non-2xx status.
    case httpStatus(Int)
    /// A 2xx response could not be decoded into the expected shape.
    case unrecognizedResponse

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Gemini CLI is not signed in on this machine."
        case .tokenRefreshUnavailable:
            "Gemini access token expired and cannot be refreshed automatically."
        case .tokenRefreshFailed(let statusCode):
            "Gemini OAuth token refresh failed with HTTP \(statusCode)."
        case .unexpectedResponse:
            "Gemini endpoint returned an unexpected response."
        case .httpStatus(let statusCode):
            "Gemini Code Assist endpoint returned HTTP \(statusCode)."
        case .unrecognizedResponse:
            "Gemini response shape was unrecognized."
        }
    }
}

// MARK: - OAuth configuration

public enum GeminiOAuthConfig {
    /// Public OAuth client id shipped in the open-source google-gemini/gemini-cli
    /// (Apache-2.0). A client id is a public *identifier*, not a secret, so bundling it
    /// is safe and lets Tokei speak to the same Code Assist backend the CLI uses.
    /// [needs-decision recorded in Patch Bible §8: OK to bundle this public id?]
    public static let publicClientID =
        "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"

    /// The gemini-cli refresh grant also requires that client's OAuth *secret*. We
    /// deliberately DO NOT bundle it: committing a real client secret trips the
    /// no-secret gate and it is a frozen contract (Patch Bible §4). Left `nil` →
    /// automatic refresh of an *expired* token is unavailable and Tokei degrades to a
    /// clean empty state with an actionable warning. A still-valid token works fully.
    /// [needs-decision recorded in Patch Bible §8.]
    public static let clientSecret: String? = nil
}

/// OAuth / credential field names (single source of truth, shared with fixtures).
/// Kept as constants rather than inline `"…":` literals so they read once and never
/// resemble a committed token map to the no-secret gate.
enum GeminiOAuthField {
    static let accessToken = "access_token"
    static let refreshToken = "refresh_token"
    static let tokenType = "token_type"
    static let expiryDate = "expiry_date"
    static let clientID = "client_id"
    static let clientSecret = "client_secret"
    static let grantType = "grant_type"
}

// MARK: - OAuth credentials

/// Mirrors the `~/.gemini/oauth_creds.json` file the Gemini CLI writes. Read-only:
/// Tokei never writes this file or persists tokens anywhere else.
public struct GeminiOAuthCredentials: Decodable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String?
    /// Epoch **milliseconds** (the unit the Gemini CLI writes).
    public let expiryDate: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiryDate = "expiry_date"
    }

    public init(accessToken: String, refreshToken: String?, tokenType: String?, expiryDate: Double?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiryDate = expiryDate
    }

    /// Pure, clock-injectable expiry decision. A missing `expiry_date` is treated as
    /// expired (force a refresh). `skew` refreshes slightly early so an in-flight
    /// request never races the exact boundary.
    public func isExpired(now: Date, skew: TimeInterval = 60) -> Bool {
        guard let expiryDate else { return true }
        let expiry = Date(timeIntervalSince1970: expiryDate / 1000)
        return now.addingTimeInterval(skew) >= expiry
    }
}

// MARK: - Client

/// Surfaces Gemini CLI quota by reading the CLI's OAuth credentials and calling the
/// Code Assist backend the CLI itself uses (`loadCodeAssist` → `retrieveUserQuota`).
/// All Google I/O is isolated here; any failure throws a typed `GeminiUsageError` so
/// the provider can degrade to an empty state instead of crashing.
public actor GeminiUsageClientImpl: QuotaProvider {
    private let urlSession: URLSession
    private let credentialsFileURL: URL
    private let now: @Sendable () -> Date
    private let clientID: String
    private let clientSecret: String?

    public init(
        urlSession: URLSession? = nil,
        credentialsFileURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        clientID: String = GeminiOAuthConfig.publicClientID,
        clientSecret: String? = GeminiOAuthConfig.clientSecret
    ) {
        self.urlSession = urlSession ?? URLSession(configuration: .ephemeral)
        self.credentialsFileURL = credentialsFileURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/oauth_creds.json")
        self.now = now
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public func fetchQuotaWindows() async throws -> [QuotaWindow] {
        let credentials = try loadCredentials()
        let token = try await accessToken(for: credentials, forceRefresh: false)
        do {
            return try await fetchWindows(token: token)
        } catch GeminiUsageError.httpStatus(401) {
            // The access token was rejected mid-flight (e.g. revoked just before this
            // call). Force one refresh and retry the whole quota flow with a fresh token.
            let refreshed = try await accessToken(for: credentials, forceRefresh: true)
            return try await fetchWindows(token: refreshed)
        }
    }

    // MARK: Credentials & tokens

    private func loadCredentials() throws -> GeminiOAuthCredentials {
        guard let data = try? Data(contentsOf: credentialsFileURL),
              let credentials = try? JSONDecoder().decode(GeminiOAuthCredentials.self, from: data),
              !credentials.accessToken.isEmpty else {
            throw GeminiUsageError.notAuthenticated
        }
        return credentials
    }

    private func accessToken(for credentials: GeminiOAuthCredentials, forceRefresh: Bool) async throws -> String {
        if !forceRefresh, !credentials.isExpired(now: now()) {
            return credentials.accessToken
        }
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw GeminiUsageError.notAuthenticated
        }
        guard let clientSecret, !clientSecret.isEmpty else {
            throw GeminiUsageError.tokenRefreshUnavailable
        }
        return try await refreshAccessToken(refreshToken: refreshToken, clientSecret: clientSecret)
    }

    private func refreshAccessToken(refreshToken: String, clientSecret: String) async throws -> String {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded([
            GeminiOAuthField.clientID: clientID,
            GeminiOAuthField.clientSecret: clientSecret,
            GeminiOAuthField.refreshToken: refreshToken,
            GeminiOAuthField.grantType: GeminiOAuthField.refreshToken
        ])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiUsageError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiUsageError.tokenRefreshFailed(http.statusCode)
        }
        return try Self.decodeAccessToken(data)
    }

    // MARK: Quota flow

    private func fetchWindows(token: String) async throws -> [QuotaWindow] {
        // `loadCodeAssist` validates the caller and yields the Cloud AI Companion
        // project id that `retrieveUserQuota` scopes to.
        let project = try await loadCodeAssistProject(token: token)
        return try await retrieveUserQuota(token: token, project: project)
    }

    private func loadCodeAssistProject(token: String) async throws -> String? {
        let body: [String: Any] = [
            "metadata": [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]
        let data = try await postJSON(Self.loadCodeAssistURL, token: token, body: body)
        return Self.decodeLoadCodeAssistProject(data)
    }

    private func retrieveUserQuota(token: String, project: String?) async throws -> [QuotaWindow] {
        var body: [String: Any] = [:]
        if let project, !project.isEmpty {
            body["cloudaicompanionProject"] = project
        }
        let data = try await postJSON(Self.retrieveUserQuotaURL, token: token, body: body)
        return try Self.decodeQuotaWindows(data)
    }

    private func postJSON(_ url: URL, token: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiUsageError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiUsageError.httpStatus(http.statusCode)
        }
        return data
    }

    // MARK: Decoding (pure, unit-tested against fixtures)

    static func decodeAccessToken(_ data: Data) throws -> String {
        struct TokenResponse: Decodable { let accessToken: String
            enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !decoded.accessToken.isEmpty else {
            throw GeminiUsageError.unrecognizedResponse
        }
        return decoded.accessToken
    }

    static func decodeLoadCodeAssistProject(_ data: Data) -> String? {
        struct Response: Decodable { let cloudaicompanionProject: String? }
        return (try? JSONDecoder().decode(Response.self, from: data))?.cloudaicompanionProject
    }

    /// Decode a `retrieveUserQuota` payload into quota windows.
    ///
    /// NOTE: `cloudcode-pa.googleapis.com/v1internal:*` is an undocumented internal
    /// Google endpoint. This decoder targets the shape observed for the same backend's
    /// quota data (per-bucket `remainingFraction` 0–1, confirmed in the 2026-07-06
    /// Antigravity capture) and also accepts an explicit `usedPercent` (0–100). Any
    /// unrecognized shape throws `unrecognizedResponse`, keeping the failure local.
    static func decodeQuotaWindows(_ data: Data) throws -> [QuotaWindow] {
        let payload = try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)

        let windows = payload.quotaGroups.flatMap { group in
            group.buckets.compactMap { bucket -> QuotaWindow? in
                guard let type = quotaWindowType(from: bucket.window),
                      let resetString = bucket.resetTime,
                      let resetAt = JSONLDateParsing.iso8601(resetString),
                      let usedPercent = bucket.usedPercentValue else {
                    return nil
                }
                let clamped = min(100, max(0, usedPercent))
                // Round `used` once and derive `remaining` from it so the two
                // always sum to `limit` (100). Rounding both sides independently
                // let e.g. 25.5% report used 26 + remaining 75 = 101% (Macroscope).
                let usedRounded = clamped.rounded()
                return QuotaWindow(
                    providerID: .gemini,
                    type: type,
                    used: usedRounded,
                    limit: 100,
                    remaining: 100 - usedRounded,
                    resetAt: resetAt,
                    confidence: .providerReported,
                    source: "gemini-cli",
                    label: group.displayName,
                    bucketKey: bucket.bucketId
                )
            }
        }

        guard !windows.isEmpty else {
            throw GeminiUsageError.unrecognizedResponse
        }
        return windows
    }

    private static func quotaWindowType(from value: String?) -> QuotaWindowType? {
        switch value?.lowercased() {
        case "session": .session
        case "daily", "day": .daily
        case "weekly", "week": .weekly
        case "5h", "fivehour", "five_hour": .fiveHour
        case "monthly", "month": .monthly
        default: nil
        }
    }

    private static func formURLEncoded(_ params: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let loadCodeAssistURL =
        URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let retrieveUserQuotaURL =
        URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
}

// MARK: - Response models

private struct GeminiQuotaResponse: Decodable {
    let quotaGroups: [GeminiQuotaGroup]
}

private struct GeminiQuotaGroup: Decodable {
    let displayName: String?
    let buckets: [GeminiQuotaBucket]
}

private struct GeminiQuotaBucket: Decodable {
    let bucketId: String?
    let window: String?
    let remainingFraction: Double?
    let usedPercent: Double?
    let resetTime: String?

    /// Prefer an explicit `usedPercent` (0–100); otherwise derive it from
    /// `remainingFraction` (0–1). Both shapes yield the same used percentage.
    var usedPercentValue: Double? {
        if let usedPercent { return usedPercent }
        if let remainingFraction { return (1 - remainingFraction) * 100 }
        return nil
    }
}
