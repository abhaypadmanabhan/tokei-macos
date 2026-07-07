import Foundation

public protocol CursorUsageClient: Sendable {
    func fetchUsage(bearerToken: String) async throws -> CursorUsageResponse
    func fetchStripeProfile(bearerToken: String) async throws -> CursorStripeProfile
}

public struct CursorUsageResponse: Sendable {
    public let quotaWindows: [QuotaWindow]
    public let warnings: [ProviderWarning]

    public init(quotaWindows: [QuotaWindow] = [], warnings: [ProviderWarning] = []) {
        self.quotaWindows = quotaWindows
        self.warnings = warnings
    }
}

public struct CursorStripeProfile: Sendable, Decodable {
    public let membershipType: String?
    public let subscriptionStatus: String?
    public let individualMembershipType: String?
    public let isYearlyPlan: Bool?
    public let isOnBillableAuto: Bool?
    public let customerBalance: Double?
    public let pendingCancellationDate: String?
    public let lastPaymentFailed: Bool?

    public init(
        membershipType: String? = nil,
        subscriptionStatus: String? = nil,
        individualMembershipType: String? = nil,
        isYearlyPlan: Bool? = nil,
        isOnBillableAuto: Bool? = nil,
        customerBalance: Double? = nil,
        pendingCancellationDate: String? = nil,
        lastPaymentFailed: Bool? = nil
    ) {
        self.membershipType = membershipType
        self.subscriptionStatus = subscriptionStatus
        self.individualMembershipType = individualMembershipType
        self.isYearlyPlan = isYearlyPlan
        self.isOnBillableAuto = isOnBillableAuto
        self.customerBalance = customerBalance
        self.pendingCancellationDate = pendingCancellationDate
        self.lastPaymentFailed = lastPaymentFailed
    }

    public var planWarning: ProviderWarning {
        ProviderWarning(message: "Plan: \(planLabel)", level: .info)
    }

    public var planLabel: String {
        var parts = [displayPlanName]
        if let isYearlyPlan {
            parts.append(isYearlyPlan ? "yearly" : "monthly")
        }
        if let isOnBillableAuto {
            parts.append(isOnBillableAuto ? "auto-billing on" : "auto-billing off")
        }
        return parts.joined(separator: " · ")
    }

    private var displayPlanName: String {
        let rawPlan = nonEmpty(membershipType) ?? nonEmpty(individualMembershipType) ?? "unknown"
        return rawPlan
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public enum CursorUsageError: Error, Sendable {
    case unexpectedResponse
    case httpStatus(Int)
}

public actor CursorUsageClientImpl: CursorUsageClient {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchUsage(bearerToken: String) async throws -> CursorUsageResponse {
        var request = URLRequest(url: Self.endpointURL)
        // SECURITY: the token leaves the process only as this Bearer header over TLS.
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CursorUsageError.httpStatus(httpResponse.statusCode)
        }
        return CursorUsageResponse.decode(data, providerID: .cursor)
    }

    public func fetchStripeProfile(bearerToken: String) async throws -> CursorStripeProfile {
        var request = URLRequest(url: Self.stripeProfileURL)
        // SECURITY: the token leaves the process only as this Bearer header over TLS.
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CursorUsageError.httpStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(CursorStripeProfile.self, from: data)
    }

    private static let endpointURL = URL(string: "https://api2.cursor.sh/auth/usage")!
    private static let stripeProfileURL = URL(string: "https://api2.cursor.sh/auth/full_stripe_profile")!
}

extension CursorUsageResponse {
    /// Defensive decode of the real `api2.cursor.sh/auth/usage` shape (verified
    /// 2026-07-06):
    /// ```
    /// { "<model>": { "numRequests": Int, "numRequestsTotal": Int, "numTokens": Int,
    ///               "maxRequestUsage": Int?, "maxTokenUsage": Int? }, ...,
    ///   "startOfMonth": "<ISO8601>" }
    /// ```
    /// Per the app's quota convention, `QuotaWindow.used` is a **percent 0–100** with
    /// `limit == 100` — so a monthly gauge is emitted only for models that actually
    /// carry a request cap (`maxRequestUsage`). Uncapped plans (Pro often reports
    /// `maxRequestUsage == nil`) surface an honest request-count info warning instead
    /// of a fabricated gauge. Tolerates shape drift by warning, never throwing.
    static func decode(_ data: Data, providerID: ProviderID) -> CursorUsageResponse {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return CursorUsageResponse(
                warnings: [ProviderWarning(message: "Cursor usage response was not valid JSON.", level: .warning)]
            )
        }

        let startOfMonth = (json["startOfMonth"] as? String).flatMap(parseISODate)
        let resetAt = startOfMonth.flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }

        var sawModel = false
        var totalRequests = 0
        var windows: [QuotaWindow] = []

        for (key, value) in json where key != "startOfMonth" {
            guard let model = value as? [String: Any],
                  let numRequests = intValue(model["numRequests"]) else { continue }
            sawModel = true
            totalRequests += numRequests

            if let maxRequests = intValue(model["maxRequestUsage"]), maxRequests > 0 {
                let usedPercent = min(100.0, Double(numRequests) / Double(maxRequests) * 100.0)
                windows.append(QuotaWindow(
                    providerID: providerID,
                    type: .monthly,
                    used: usedPercent,
                    limit: 100,
                    remaining: 100 - usedPercent,
                    resetAt: resetAt,
                    confidence: .providerReported,
                    source: "api2.cursor.sh/auth/usage (\(key))"
                ))
            }
        }

        guard sawModel else {
            return CursorUsageResponse(
                warnings: [ProviderWarning(
                    message: "Cursor usage response shape was unrecognized.",
                    level: .warning
                )]
            )
        }

        let since = startOfMonth.map { " since \(mediumDate($0))" } ?? ""
        let warning = ProviderWarning(
            message: "Cursor: \(totalRequests) requests this billing month\(since).",
            level: .info
        )

        return CursorUsageResponse(
            quotaWindows: windows.sorted { $0.source < $1.source },
            warnings: [warning]
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
