import Foundation
import os

/// One personal billing meter for the current month, summed over GitHub's `usageItems`.
public struct CopilotBillingMeter: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case premiumRequests = "premium_request"
        case aiCredits = "ai_credit"
    }

    public let kind: Kind
    public let itemCount: Int
    /// Everything used this month.
    public let grossQuantity: Double
    /// The part the plan's included allowance covered.
    public let discountQuantity: Double
    /// The part that is billed.
    public let netQuantity: Double
    /// Billed amount in USD.
    public let netAmount: Double
}

public struct CopilotBillingUsage: Sendable, Equatable {
    public let year: Int
    public let month: Int
    /// Meters whose endpoint answered; a meter GitHub does not offer this account (404) is absent.
    public let meters: [CopilotBillingMeter]

    /// No usage line at all: what a seat billed to an organization or enterprise looks like,
    /// since the user-level endpoints leave those out.
    public var isEmpty: Bool { meters.allSatisfy { $0.itemCount == 0 } }
}

/// Parses GitHub's user billing usage reports
/// (`GET /users/{username}/settings/billing/{premium_request|ai_credit}/usage`,
/// https://docs.github.com/en/rest/billing/usage, API version 2026-03-10):
/// `{ "timePeriod": { "year", "month"? }, "user", "usageItems": [ { grossQuantity,
/// discountQuantity, netQuantity, netAmount, ... } ] }`.
public enum CopilotBillingParser {
    public static let apiVersion = "2026-03-10"

    /// One report: the summed meter and the period GitHub says it covers (month may be absent).
    public struct Report: Sendable, Equatable {
        public let meter: CopilotBillingMeter
        public let year: Int?
        public let month: Int?
    }

    public static func meter(kind: CopilotBillingMeter.Kind, from data: Data) throws -> Report {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["usageItems"] as? [[String: Any]] else {
            throw OfficialUsageError.unexpectedResponse
        }
        func sum(_ key: String) -> Double {
            items.reduce(0) { total, item in
                let value = (item[key] as? NSNumber)?.doubleValue ?? 0
                return value.isFinite ? total + value : total
            }
        }
        let period = root["timePeriod"] as? [String: Any]
        let meter = CopilotBillingMeter(
            kind: kind,
            itemCount: items.count,
            grossQuantity: sum("grossQuantity"),
            discountQuantity: sum("discountQuantity"),
            netQuantity: sum("netQuantity"),
            netAmount: sum("netAmount")
        )
        return Report(
            meter: meter,
            year: (period?["year"] as? NSNumber)?.intValue,
            month: (period?["month"] as? NSNumber)?.intValue
        )
    }

    /// GitHub's `/user` login, only when it is a valid GitHub handle (it goes into a path).
    public static func login(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = root["login"] as? String,
              login.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", options: .regularExpression) != nil else {
            throw OfficialUsageError.unexpectedResponse
        }
        return login
    }

    /// One `.credits` window per meter with usage lines. GitHub reports counts, not the
    /// plan's allowance, so `limit` stays `nil`: Tokei shows "used", never a made-up percent.
    /// The meter resets with the calendar month (UTC), which is the period GitHub reported.
    public static func quotaWindows(from usage: CopilotBillingUsage, observedAt: Date) -> [QuotaWindow] {
        let reset = startOfNextMonthUTC(year: usage.year, month: usage.month)
        return usage.meters.filter { $0.itemCount > 0 }.map { meter in
            QuotaWindow(
                providerID: .copilot,
                type: .credits,
                used: meter.grossQuantity,
                limit: nil,
                remaining: nil,
                resetAt: reset,
                confidence: .providerReported,
                source: "api.github.com billing \(meter.kind.rawValue)/usage",
                label: label(meter.kind),
                bucketKey: bucketKey(meter.kind),
                observedAt: observedAt
            )
        }
    }

    /// What GitHub billed this month across the meters, when any meter answered.
    public static func billedCost(from usage: CopilotBillingUsage) -> CostUsage? {
        guard !usage.isEmpty else { return nil }
        return CostUsage(
            amount: usage.meters.reduce(0) { $0 + $1.netAmount },
            currency: "USD",
            confidence: .providerReported
        )
    }

    public static func bucketKey(_ kind: CopilotBillingMeter.Kind) -> String {
        switch kind {
        case .premiumRequests: return "copilot_premium_requests"
        case .aiCredits: return "copilot_ai_credits"
        }
    }

    static func label(_ kind: CopilotBillingMeter.Kind) -> String {
        switch kind {
        case .premiumRequests: return "Premium requests"
        case .aiCredits: return "AI credits"
        }
    }

    static func startOfNextMonthUTC(year: Int, month: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: start)
    }
}

public protocol CopilotBillingFetching: Sendable {
    func fetchUsage(token: String) async throws -> CopilotBillingUsage
}

/// Reads the signed-in person's own Copilot billing with a fine-grained personal access
/// token (user permission "Plan": read): `GET /user` for the handle, then the
/// premium-request and AI-credit usage reports for the current month.
public struct CopilotBillingClient: CopilotBillingFetching {
    static let apiBase = URL(string: "https://api.github.com")!

    private let transport: BearerUsageTransport
    private let now: @Sendable () -> Date

    public init(
        urlSession: URLSession? = nil,
        cooldownURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: (@Sendable (TimeInterval) async -> Void)? = nil
    ) {
        let cooldownURL = cooldownURL ?? BearerUsageTransport.defaultStorageDirectory()
            .appendingPathComponent("copilot-billing-cooldown.json")
        self.now = now
        transport = BearerUsageTransport(
            urlSession: urlSession ?? UsageHTTPSession.shared,
            cooldown: CooldownStore(cooldownURL: cooldownURL, now: now),
            headers: [
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": CopilotBillingParser.apiVersion
            ],
            logger: Logger(subsystem: "ai.padzy.tokei", category: "CopilotBillingClient"),
            sleep: sleep ?? BearerUsageTransport.defaultSleep,
            now: now
        )
    }

    public func fetchUsage(token: String) async throws -> CopilotBillingUsage {
        let login = try CopilotBillingParser.login(
            from: try await transport.get(Self.apiBase.appendingPathComponent("user"), token: token)
        )
        var meters: [CopilotBillingMeter] = []
        var period: (year: Int?, month: Int?) = (nil, nil)
        for kind in CopilotBillingMeter.Kind.allCases {
            let url = Self.apiBase.appendingPathComponent("users/\(login)/settings/billing/\(kind.rawValue)/usage")
            do {
                let body = try await transport.get(url, token: token)
                let parsed = try CopilotBillingParser.meter(kind: kind, from: body)
                meters.append(parsed.meter)
                period = (period.year ?? parsed.year, period.month ?? parsed.month)
            } catch OfficialUsageError.notFound {
                continue
            }
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let today = utc.dateComponents([.year, .month], from: now())
        return CopilotBillingUsage(
            year: period.year ?? today.year ?? 1970,
            month: period.month ?? today.month ?? 1,
            meters: meters
        )
    }
}
