import Foundation

public actor CodexJSONLParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        public let dailyTotals: [Date: Int]
        public let quotaWindows: [QuotaWindow]
        public let deltaReportedTotalTokens: Int
        public let finalReportedTotalTokens: Int
        public let warnings: [ProviderWarning]
    }

    private let calendar: Calendar
    private let now: () -> Date

    public init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(logSources: [LogSource]) async -> AggregateUsage {
        var warnings: [ProviderWarning] = []
        let referenceDate = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: referenceDate)
        var latestRateLimits: CodexRateLimitSnapshot?
        var deltaReportedTotalTokens = 0
        var finalTotalsBySession: [String: CodexSessionFinalTotal] = [:]

        for source in logSources {
            do {
                let malformedCount = try await parseFile(at: source.url) { record in
                    windows.accumulate(
                        record.deltaUsage,
                        timestamp: record.timestamp,
                        dailyTotal: record.deltaReportedTotalTokens
                    )
                    deltaReportedTotalTokens += record.deltaReportedTotalTokens

                    if let cumulativeTotal = record.cumulativeReportedTotalTokens {
                        let key = source.sessionID ?? source.url.path
                        let current = finalTotalsBySession[key]
                        if current == nil || record.isNewerThan(current!) {
                            finalTotalsBySession[key] = CodexSessionFinalTotal(
                                timestamp: record.timestamp,
                                totalTokens: cumulativeTotal
                            )
                        }
                    }

                    if let rateLimits = record.rateLimits,
                       latestRateLimits == nil || rateLimits.timestamp > latestRateLimits!.timestamp {
                        latestRateLimits = rateLimits
                    }
                }

                if malformedCount > 0 {
                    warnings.append(ProviderWarning(
                        message: "\(source.url.lastPathComponent): \(malformedCount) malformed line(s) skipped",
                        level: .warning
                    ))
                }
            } catch {
                warnings.append(ProviderWarning(
                    message: "Failed to parse \(source.url.lastPathComponent): \(error.localizedDescription)",
                    level: .warning
                ))
            }
        }

        let snapshot = windows.snapshot()
        return AggregateUsage(
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            lifetime: snapshot.lifetime,
            dailyTotals: snapshot.dailyTotals,
            quotaWindows: quotaWindows(from: latestRateLimits, referenceDate: referenceDate),
            deltaReportedTotalTokens: deltaReportedTotalTokens,
            finalReportedTotalTokens: finalTotalsBySession.values.map(\.totalTokens).reduce(0, +),
            warnings: warnings
        )
    }
}

enum CodexLineParseOutcome: Sendable {
    case usage(CodexUsageRecord)
    case skipped
    case malformed
}

struct CodexUsageRecord: Sendable {
    let timestamp: Date?
    let deltaUsage: TokenUsage
    let deltaReportedTotalTokens: Int
    let cumulativeReportedTotalTokens: Int?
    let rateLimits: CodexRateLimitSnapshot?

    func isNewerThan(_ finalTotal: CodexSessionFinalTotal) -> Bool {
        switch (timestamp, finalTotal.timestamp) {
        case let (lhs?, rhs?):
            return lhs >= rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return true
        }
    }
}

struct CodexSessionFinalTotal: Sendable {
    let timestamp: Date?
    let totalTokens: Int
}

struct CodexRateLimitSnapshot: Sendable {
    let timestamp: Date
    let planType: String?
    let primary: CodexRateLimit?
    let secondary: CodexRateLimit?
}

struct CodexRateLimit: Sendable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Date?
}

extension CodexJSONLParser {
    func parseFile(at url: URL, onRecord: (CodexUsageRecord) -> Void) async throws -> Int {
        var malformedCount = 0
        for try await line in url.lines {
            guard let data = line.data(using: .utf8) else { continue }
            switch parseLine(data) {
            case .usage(let record):
                onRecord(record)
            case .skipped:
                break
            case .malformed:
                malformedCount += 1
            }
        }
        return malformedCount
    }

    func parseLine(_ data: Data) -> CodexLineParseOutcome {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }

        guard json["type"] as? String == "event_msg",
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "token_count" else {
            return .skipped
        }

        guard let info = payload["info"] as? [String: Any],
              let lastUsage = info["last_token_usage"] as? [String: Any] else {
            return .malformed
        }

        let timestamp = JSONLDateParsing.parseTimestamp(from: json)
        let deltaUsage = tokenUsage(from: lastUsage)
        let deltaReportedTotal = intValue(lastUsage["total_tokens"]) ?? deltaUsage.totalTokens ?? 0
        let cumulativeUsage = info["total_token_usage"] as? [String: Any]
        let cumulativeReportedTotal = cumulativeUsage.flatMap { intValue($0["total_tokens"]) }

        return .usage(CodexUsageRecord(
            timestamp: timestamp,
            deltaUsage: deltaUsage,
            deltaReportedTotalTokens: deltaReportedTotal,
            cumulativeReportedTotalTokens: cumulativeReportedTotal,
            rateLimits: rateLimits(from: payload["rate_limits"], timestamp: timestamp)
        ))
    }

    private func tokenUsage(from json: [String: Any]) -> TokenUsage {
        let rawInput = intValue(json["input_tokens"]) ?? 0
        let rawOutput = intValue(json["output_tokens"]) ?? 0
        let cacheRead = intValue(json["cached_input_tokens"]) ?? 0
        let reasoning = intValue(json["reasoning_output_tokens"]) ?? 0

        return TokenUsage(
            inputTokens: max(0, rawInput - cacheRead),
            outputTokens: max(0, rawOutput - reasoning),
            cacheReadTokens: cacheRead,
            cacheCreationTokens: 0,
            reasoningTokens: reasoning,
            confidence: .localParsed
        )
    }

    private func rateLimits(from value: Any?, timestamp: Date?) -> CodexRateLimitSnapshot? {
        guard let timestamp,
              let json = value as? [String: Any] else {
            return nil
        }

        return CodexRateLimitSnapshot(
            timestamp: timestamp,
            planType: json["plan_type"] as? String,
            primary: rateLimit(from: json["primary"]),
            secondary: rateLimit(from: json["secondary"])
        )
    }

    private func rateLimit(from value: Any?) -> CodexRateLimit? {
        guard let json = value as? [String: Any] else {
            return nil
        }
        return CodexRateLimit(
            usedPercent: doubleValue(json["used_percent"]),
            windowMinutes: intValue(json["window_minutes"]),
            resetsAt: intValue(json["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func quotaWindows(
        from snapshot: CodexRateLimitSnapshot?,
        referenceDate: Date
    ) -> [QuotaWindow] {
        guard let snapshot else { return [] }
        let confidence: MetricConfidence = referenceDate.timeIntervalSince(snapshot.timestamp) > 86_400
            ? .estimated
            : .providerReported

        var windows: [QuotaWindow] = []
        if let primary = snapshot.primary {
            windows.append(quotaWindow(
                type: .session,
                rateLimit: primary,
                planType: snapshot.planType,
                confidence: confidence
            ))
        }
        if let secondary = snapshot.secondary {
            windows.append(quotaWindow(
                type: .weekly,
                rateLimit: secondary,
                planType: snapshot.planType,
                confidence: confidence
            ))
        }
        return windows
    }

    private func quotaWindow(
        type: QuotaWindowType,
        rateLimit: CodexRateLimit,
        planType: String?,
        confidence: MetricConfidence
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .codex,
            type: type,
            used: rateLimit.usedPercent,
            limit: 100,
            remaining: rateLimit.usedPercent.map { 100 - $0 },
            resetAt: rateLimit.resetsAt,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), \(sourceWindow(type: type, minutes: rateLimit.windowMinutes)))"
        )
    }

    private func sourcePlan(_ planType: String?) -> String {
        guard let planType, !planType.isEmpty else { return "unknown plan" }
        return "\(planType) plan"
    }

    private func sourceWindow(type: QuotaWindowType, minutes: Int?) -> String {
        if minutes == 300 {
            return "5h window"
        }
        if minutes == 10_080 {
            return "weekly window"
        }
        if let minutes, minutes.isMultiple(of: 60) {
            return "\(minutes / 60)h window"
        }
        if let minutes {
            return "\(minutes)m window"
        }
        return type == .weekly ? "weekly window" : "session window"
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Double {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }
}
