import Foundation

struct WindowedTokenUsage: Sendable {
    let today: TokenUsage
    let week: TokenUsage
    let month: TokenUsage
    let lifetime: TokenUsage
    let dailyTotals: [Date: Int]
}

struct UsageWindows: Sendable {
    private let calendar: Calendar
    private let todayStart: Date
    private let weekStart: Date
    private let monthStart: Date

    private var today: TokenUsage
    private var week: TokenUsage
    private var month: TokenUsage
    private var lifetime: TokenUsage
    private var dailyTotals: [Date: Int] = [:]

    /// `emptyConfidence` seeds the accumulators, so it becomes the floor for the
    /// resulting windows (`TokenUsage.merging` keeps the least-trustworthy input).
    /// Local log parsers keep the `.localParsed` default; a provider whose numbers
    /// come straight from its own backend (e.g. Cursor's web usage export) passes
    /// `.providerReported` so the windows aren't under-labelled.
    init(calendar: Calendar, referenceDate: Date, emptyConfidence: MetricConfidence = .localParsed) {
        self.calendar = calendar
        self.todayStart = calendar.startOfDay(for: referenceDate)
        self.weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        self.monthStart = calendar.date(byAdding: .month, value: -1, to: todayStart) ?? todayStart
        let seed = Self.emptyUsage(emptyConfidence)
        self.today = seed
        self.week = seed
        self.month = seed
        self.lifetime = seed
    }

    mutating func accumulate(_ usage: TokenUsage, timestamp: Date?, dailyTotal: Int) {
        lifetime = lifetime.merging(usage)

        guard let timestamp else { return }
        if timestamp >= todayStart { today = today.merging(usage) }
        if timestamp >= weekStart { week = week.merging(usage) }
        if timestamp >= monthStart { month = month.merging(usage) }
        dailyTotals[calendar.startOfDay(for: timestamp), default: 0] += dailyTotal
    }

    func snapshot() -> WindowedTokenUsage {
        WindowedTokenUsage(
            today: today,
            week: week,
            month: month,
            lifetime: lifetime,
            dailyTotals: dailyTotals
        )
    }

    static func emptyUsage(_ confidence: MetricConfidence = .localParsed) -> TokenUsage {
        TokenUsage(
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0,
            confidence: confidence
        )
    }
}

enum JSONLDateParsing {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseTimestamp(from json: [String: Any]) -> Date? {
        if let ts = json["timestamp"] as? TimeInterval {
            return Date(timeIntervalSince1970: ts)
        }
        if let tsString = json["timestamp"] as? String {
            if let date = fractional.date(from: tsString) {
                return date
            }
            if let date = standard.date(from: tsString) {
                return date
            }
        }
        return nil
    }
}
