import Foundation
import os

/// One OpenCode Go meter as the official endpoint reports it.
public struct OpencodeGoMeter: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// The 5-hour rolling limit.
        case rolling
        case weekly
        case monthly
    }

    public let kind: Kind
    /// `true` when the server says `"status": "rate-limited"` (the limit is used up).
    public let isRateLimited: Bool
    /// Whole number 0...100, as reported.
    public let percent: Double
    public let resetsAt: Date?
}

/// Parses `GET https://opencode.ai/inference/go/v1/usage` (https://opencode.ai/docs/console/go/):
/// `{ "usage": { "rolling" | "weekly" | "monthly": { status, percent, resetsAt } } }`.
public enum OpencodeGoUsageParser {
    public static let source = "opencode.ai/inference/go/v1/usage"

    public static func meters(from data: Data) throws -> [OpencodeGoMeter] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            throw OfficialUsageError.unexpectedResponse
        }
        return OpencodeGoMeter.Kind.allCases.compactMap { kind in
            guard let meter = usage[kind.rawValue] as? [String: Any],
                  let percent = (meter["percent"] as? NSNumber)?.doubleValue, percent.isFinite else { return nil }
            return OpencodeGoMeter(
                kind: kind,
                isRateLimited: (meter["status"] as? String)?.lowercased() == "rate-limited",
                percent: min(100, max(0, percent)),
                resetsAt: (meter["resetsAt"] as? String).flatMap(parseDate)
            )
        }
    }

    /// Tokei's percent-gauge convention: `used` is the percent and `limit` is 100.
    public static func quotaWindows(from meters: [OpencodeGoMeter], observedAt: Date) -> [QuotaWindow] {
        meters.map { meter in
            QuotaWindow(
                providerID: .opencode,
                type: windowType(meter.kind),
                used: meter.percent,
                limit: 100,
                remaining: 100 - meter.percent,
                resetAt: meter.resetsAt,
                confidence: .providerReported,
                source: source,
                label: label(meter.kind),
                bucketKey: "opencode_go_\(meter.kind.rawValue)",
                observedAt: observedAt,
                windowDuration: duration(meter.kind)
            )
        }
    }

    /// The 403 body's `error.message` (e.g. "OpenCode Go subscription required."), only when
    /// it is safe to show.
    static func entitlementMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return nil }
        return BearerUsageTransport.displayableMessage(error["message"] as? String)
    }

    static func label(_ kind: OpencodeGoMeter.Kind) -> String {
        switch kind {
        case .rolling: return "Go 5-hour"
        case .weekly: return "Go weekly"
        case .monthly: return "Go monthly"
        }
    }

    private static func windowType(_ kind: OpencodeGoMeter.Kind) -> QuotaWindowType {
        switch kind {
        case .rolling: return .fiveHour
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }

    /// Only the lengths the docs state: rolling is the 5-hour limit, weekly is a week.
    private static func duration(_ kind: OpencodeGoMeter.Kind) -> TimeInterval? {
        switch kind {
        case .rolling: return 5 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        case .monthly: return nil
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

public protocol OpencodeGoUsageFetching: Sendable {
    func fetchMeters(apiKey: String) async throws -> [OpencodeGoMeter]
}

public struct OpencodeGoUsageClient: OpencodeGoUsageFetching {
    static let usageURL = URL(string: "https://opencode.ai/inference/go/v1/usage")!

    private let transport: BearerUsageTransport

    public init(
        urlSession: URLSession? = nil,
        cooldownURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: (@Sendable (TimeInterval) async -> Void)? = nil
    ) {
        let cooldownURL = cooldownURL ?? BearerUsageTransport.defaultStorageDirectory()
            .appendingPathComponent("opencode-go-usage-cooldown.json")
        transport = BearerUsageTransport(
            urlSession: urlSession ?? UsageHTTPSession.shared,
            cooldown: CooldownStore(cooldownURL: cooldownURL, now: now),
            headers: ["Accept": "application/json"],
            logger: Logger(subsystem: "ai.padzy.tokei", category: "OpencodeGoUsageClient"),
            sleep: sleep ?? BearerUsageTransport.defaultSleep,
            now: now
        )
    }

    public func fetchMeters(apiKey: String) async throws -> [OpencodeGoMeter] {
        let data = try await transport.get(
            Self.usageURL,
            token: apiKey,
            forbiddenMessage: OpencodeGoUsageParser.entitlementMessage(from:)
        )
        return try OpencodeGoUsageParser.meters(from: data)
    }
}
