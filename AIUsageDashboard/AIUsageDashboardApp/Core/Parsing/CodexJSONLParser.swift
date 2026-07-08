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
    let spendControlIndividualLimit: CodexSpendControlLimit?
    let credits: CodexCreditsSnapshot?
    let rateLimitResetCredits: CodexResetBankSnapshot?
}

struct CodexRateLimit: Sendable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let limitWindowSeconds: Int?
    let windowDurationMins: Int?
    let resetsAt: Date?
    let resetsInSeconds: Int?
}

struct CodexSpendControlLimit: Sendable {
    let limit: String?
    let used: String?
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetsAt: Date?
}

struct CodexCreditsSnapshot: Sendable {
    let usedPercent: Double?
    let balance: Double?
    let limit: Double?
}

struct CodexResetBankSnapshot: Sendable {
    let available: Int?
    let count: Int?
}

private enum CodexWindowDuration {
    static let sessionSeconds = 18_000
    static let weeklySeconds = 604_800
    static let toleranceSeconds = 3_600
}

extension CodexJSONLParser {
    /// Best-effort scan for the most recently configured model, read from `turn_context`
    /// events' `payload.model`. Read-only: does not affect `parse(logSources:)` or the
    /// shape of `AggregateUsage`. This is a separate pass over the log files from
    /// `parse(logSources:)`'s token-count scan, so sources are walked newest-first
    /// (they're expected pre-sorted chronologically, as `CodexProvider.discoverLogSources()`
    /// returns them) and stop at the first file with a `turn_context` event — avoiding a
    /// second full read of every session file just to find the most recent model.
    public func detectLatestModel(logSources: [LogSource]) async -> String? {
        for source in logSources.reversed() {
            if let model = await latestModel(inFileAt: source.url) {
                return model
            }
        }
        return nil
    }

    private func latestModel(inFileAt url: URL) async -> String? {
        var model: String?
        do {
            for try await line in url.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "turn_context",
                      let payload = json["payload"] as? [String: Any],
                      let payloadModel = payload["model"] as? String else { continue }
                model = payloadModel
            }
        } catch {
            return nil
        }
        return model
    }

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

        let spendControl = json["spend_control"] as? [String: Any]
        return CodexRateLimitSnapshot(
            timestamp: timestamp,
            planType: json["plan_type"] as? String,
            primary: rateLimit(from: json["primary"], eventTimestamp: timestamp),
            secondary: rateLimit(from: json["secondary"], eventTimestamp: timestamp),
            spendControlIndividualLimit: spendControlLimit(from: spendControl?["individual_limit"]),
            credits: creditsSnapshot(from: json["credits"]),
            rateLimitResetCredits: resetBankSnapshot(from: json["rate_limit_reset_credits"])
        )
    }

    private func rateLimit(from value: Any?, eventTimestamp: Date) -> CodexRateLimit? {
        guard let json = value as? [String: Any] else {
            return nil
        }
        let resetsInSeconds = intValue(json["resets_in_seconds"])
        let resetsAt = intValue(json["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? resetsInSeconds.map { eventTimestamp.addingTimeInterval(TimeInterval($0)) }
        return CodexRateLimit(
            usedPercent: doubleValue(json["used_percent"]),
            windowMinutes: intValue(json["window_minutes"]),
            limitWindowSeconds: intValue(json["limit_window_seconds"]),
            windowDurationMins: intValue(json["window_duration_mins"]),
            resetsAt: resetsAt,
            resetsInSeconds: resetsInSeconds
        )
    }

    private func spendControlLimit(from value: Any?) -> CodexSpendControlLimit? {
        guard let json = value as? [String: Any] else { return nil }
        return CodexSpendControlLimit(
            limit: json["limit"] as? String,
            used: json["used"] as? String,
            usedPercent: doubleValue(json["used_percent"]),
            remainingPercent: doubleValue(json["remaining_percent"]),
            resetsAt: intValue(json["reset_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func creditsSnapshot(from value: Any?) -> CodexCreditsSnapshot? {
        guard let json = value as? [String: Any] else { return nil }
        return CodexCreditsSnapshot(
            usedPercent: doubleValue(json["used_percent"]),
            balance: doubleValue(json["balance"]),
            limit: doubleValue(json["limit"])
        )
    }

    private func resetBankSnapshot(from value: Any?) -> CodexResetBankSnapshot? {
        guard let json = value as? [String: Any] else { return nil }
        return CodexResetBankSnapshot(
            available: intValue(json["available"]),
            count: intValue(json["count"])
        )
    }

    private func windowDurationSeconds(for rateLimit: CodexRateLimit) -> Int? {
        if let seconds = rateLimit.limitWindowSeconds { return seconds }
        if let minutes = rateLimit.windowMinutes { return minutes * 60 }
        if let minutes = rateLimit.windowDurationMins { return minutes * 60 }
        return nil
    }

    private func quotaWindowType(
        for rateLimit: CodexRateLimit,
        positionalFallback: QuotaWindowType
    ) -> QuotaWindowType {
        guard let seconds = windowDurationSeconds(for: rateLimit) else {
            return positionalFallback
        }
        let sessionDistance = abs(seconds - CodexWindowDuration.sessionSeconds)
        let weeklyDistance = abs(seconds - CodexWindowDuration.weeklySeconds)
        if sessionDistance <= CodexWindowDuration.toleranceSeconds,
           sessionDistance <= weeklyDistance {
            return .session
        }
        if weeklyDistance <= CodexWindowDuration.toleranceSeconds {
            return .weekly
        }
        return positionalFallback
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
        var sessionWindow: QuotaWindow?
        var weeklyWindow: QuotaWindow?

        if let primary = snapshot.primary {
            let type = quotaWindowType(for: primary, positionalFallback: .session)
            let window = quotaWindow(
                type: type,
                rateLimit: primary,
                planType: snapshot.planType,
                confidence: confidence
            )
            switch type {
            case .session: sessionWindow = window
            case .weekly: weeklyWindow = window
            default: windows.append(window)
            }
        }
        if let secondary = snapshot.secondary {
            let type = quotaWindowType(for: secondary, positionalFallback: .weekly)
            let window = quotaWindow(
                type: type,
                rateLimit: secondary,
                planType: snapshot.planType,
                confidence: confidence
            )
            switch type {
            case .session where sessionWindow == nil: sessionWindow = window
            case .weekly where weeklyWindow == nil: weeklyWindow = window
            case .session: sessionWindow = window
            case .weekly: weeklyWindow = window
            default: windows.append(window)
            }
        }
        if let sessionWindow { windows.append(sessionWindow) }
        if let weeklyWindow { windows.append(weeklyWindow) }

        if let individualLimit = snapshot.spendControlIndividualLimit {
            windows.append(individualLimitWindow(
                from: individualLimit,
                planType: snapshot.planType,
                confidence: confidence
            ))
        }
        if let credits = snapshot.credits {
            if let window = purchasableCreditsWindow(
                from: credits,
                planType: snapshot.planType,
                confidence: confidence
            ) {
                windows.append(window)
            }
        }
        if let resetBank = snapshot.rateLimitResetCredits {
            if let window = resetBankWindow(
                from: resetBank,
                planType: snapshot.planType,
                confidence: confidence
            ) {
                windows.append(window)
            }
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
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), \(sourceWindowLabel(for: rateLimit, type: type)))"
        )
    }

    private func individualLimitWindow(
        from limit: CodexSpendControlLimit,
        planType: String?,
        confidence: MetricConfidence
    ) -> QuotaWindow {
        QuotaWindow(
            providerID: .codex,
            type: .credits,
            used: limit.usedPercent,
            limit: 100,
            remaining: limit.remainingPercent,
            resetAt: limit.resetsAt,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), monthly credit limit)",
            label: "Monthly credit limit",
            bucketKey: "spend_control_individual_limit"
        )
    }

    private func purchasableCreditsWindow(
        from credits: CodexCreditsSnapshot,
        planType: String?,
        confidence: MetricConfidence
    ) -> QuotaWindow? {
        guard credits.usedPercent != nil || credits.balance != nil || credits.limit != nil else {
            return nil
        }
        let used = credits.usedPercent
        let limit = credits.limit ?? (used != nil ? 100 : nil)
        let remaining: Double?
        if let used, let limit {
            remaining = limit - used
        } else {
            remaining = credits.balance
        }
        return QuotaWindow(
            providerID: .codex,
            type: .credits,
            used: used ?? credits.balance,
            limit: limit,
            remaining: remaining,
            resetAt: nil,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), purchasable credits)",
            label: "Purchasable credits",
            bucketKey: "credits"
        )
    }

    private func resetBankWindow(
        from resetBank: CodexResetBankSnapshot,
        planType: String?,
        confidence: MetricConfidence
    ) -> QuotaWindow? {
        guard let count = resetBank.available ?? resetBank.count else { return nil }
        let available = Double(count)
        return QuotaWindow(
            providerID: .codex,
            type: .credits,
            used: nil,
            limit: available,
            remaining: available,
            resetAt: nil,
            confidence: confidence,
            source: "Codex CLI rate_limits (\(sourcePlan(planType)), reset bank)",
            label: "Reset bank",
            bucketKey: "reset_bank"
        )
    }

    private func sourceWindowLabel(for rateLimit: CodexRateLimit, type: QuotaWindowType) -> String {
        if let seconds = windowDurationSeconds(for: rateLimit) {
            if abs(seconds - CodexWindowDuration.sessionSeconds) <= CodexWindowDuration.toleranceSeconds {
                return "5h window"
            }
            if abs(seconds - CodexWindowDuration.weeklySeconds) <= CodexWindowDuration.toleranceSeconds {
                return "weekly window"
            }
            if seconds.isMultiple(of: 3600) {
                return "\(seconds / 3600)h window"
            }
            return "\(seconds)s window"
        }
        if let minutes = rateLimit.windowMinutes {
            return sourceWindow(type: type, minutes: minutes)
        }
        return type == .weekly ? "weekly window" : "session window"
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
