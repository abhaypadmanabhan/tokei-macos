import Foundation

// The pure decoders behind `CursorUsageClient`. Split out of that file so the transport
// (requests, cookies, cooldown, retry) and the payload shapes can each be read on their own;
// they change for entirely different reasons — the transport when Cursor changes its auth or
// rate limiting, these when it reorders a CSV column or renames a JSON key. Nothing here
// touches the network or the clock, which is what keeps it trivially testable.

// MARK: - Token events (CSV)

/// One token-usage event from the export CSV, already split into Tokei's token
/// categories. `cacheWrite = Input(w/ Cache Write) − Input(w/o Cache Write)`.
public struct CursorUsageEvent: Sendable, Equatable {
    public let date: Date
    public let model: String
    public let inputTokens: Int
    public let cacheWriteTokens: Int
    public let cacheReadTokens: Int
    public let outputTokens: Int
    public let cost: Double

    public var totalTokens: Int { inputTokens + cacheWriteTokens + cacheReadTokens + outputTokens }

    public init(
        date: Date,
        model: String,
        inputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int,
        outputTokens: Int,
        cost: Double
    ) {
        self.date = date
        self.model = model
        self.inputTokens = inputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.cost = cost
    }
}

/// Parses the `strategy=tokens` export CSV. Column lookup is header-name driven
/// (Cursor reorders/inserts columns over time), so only the required header
/// strings matter, not their positions.
public enum CursorUsageCSV {
    public static func parseEvents(_ csv: String) -> [CursorUsageEvent] {
        let rows = csv.split(whereSeparator: \.isNewline)
        guard let headerRow = rows.first else { return [] }

        var index: [String: Int] = [:]
        for (position, name) in splitFields(headerRow).enumerated() where index[name] == nil {
            index[name] = position
        }
        // Resolve the required column positions once; positions are stable per file.
        guard let dateCol = index["Date"],
              let modelCol = index["Model"],
              let inputWithCol = index["Input (w/ Cache Write)"],
              let inputWithoutCol = index["Input (w/o Cache Write)"],
              let cacheReadCol = index["Cache Read"],
              let outputCol = index["Output Tokens"],
              let costCol = index["Cost"] else { return [] }

        func field(_ fields: [String], _ column: Int) -> String? {
            column < fields.count ? fields[column] : nil
        }

        return rows.dropFirst().compactMap { row -> CursorUsageEvent? in
            let fields = splitFields(row)
            guard let dateString = field(fields, dateCol), let date = parseDate(dateString) else {
                return nil
            }
            let inputWithout = intValue(field(fields, inputWithoutCol))
            let inputWith = intValue(field(fields, inputWithCol))
            let cacheWrite = max(0, inputWith - inputWithout)
            let cacheRead = intValue(field(fields, cacheReadCol))
            let output = intValue(field(fields, outputCol))

            // Every term is non-negative, so total > 0 already means "some usage" —
            // drops all-zero rows (e.g. errored/no-charge), keeps non-billable usage.
            let total = inputWithout + cacheWrite + cacheRead + output
            guard total > 0 else { return nil }

            return CursorUsageEvent(
                date: date,
                model: field(fields, modelCol) ?? "",
                inputTokens: inputWithout,
                cacheWriteTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                outputTokens: output,
                cost: floatValue(field(fields, costCol))
            )
        }
    }

    /// RFC4180-ish field split: honours double-quoted fields (which may contain
    /// commas) and `""` escapes. Trims surrounding whitespace on unquoted fields.
    /// Takes `StringProtocol` so it can split `Substring` rows without copying them.
    static func splitFields<S: StringProtocol>(_ line: S) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.startIndex

        while iterator < line.endIndex {
            let character = line[iterator]
            if inQuotes {
                if character == "\"" {
                    let next = line.index(after: iterator)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        iterator = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            iterator = line.index(after: iterator)
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static func intValue(_ raw: String?) -> Int {
        guard let raw else { return 0 }
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let value = Int(cleaned) { return value }
        if let value = Double(cleaned) { return Int(value) }
        return 0
    }

    private static func floatValue(_ raw: String?) -> Double {
        guard let raw else { return 0 }
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }

    /// Cursor's `Date` is ISO8601 with fractional seconds + `Z`; a bare
    /// `yyyy-MM-dd` is also accepted. All treated as UTC instants.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return JSONLDateParsing.iso8601(trimmed) ?? dayOnlyFormatter.date(from: trimmed)
    }

    private static let dayOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Usage summary (quota)

/// The plan-level utilisation Cursor reports on `usage-summary`. `usedPercent`
/// is 0…100; `nil` when the plan exposes no usable figure (never fabricated).
public struct CursorUsageSummary: Sendable, Equatable {
    public let usedPercent: Double?
    public let resetAt: Date?
    public let membershipType: String?
    public let autoPercentUsed: Double?
    public let apiPercentUsed: Double?

    public init(
        usedPercent: Double?, resetAt: Date?, membershipType: String?,
        autoPercentUsed: Double? = nil, apiPercentUsed: Double? = nil
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.membershipType = membershipType
        self.autoPercentUsed = autoPercentUsed
        self.apiPercentUsed = apiPercentUsed
    }

    /// Decodes the `usage-summary` body. Percent precedence mirrors the Cursor
    /// dashboard: `plan.totalPercentUsed` → mean(auto, api) → auto/api alone →
    /// `plan.used / plan.limit`. Returns `nil` when nothing is decodable.
    public static func decode(_ data: Data) -> CursorUsageSummary? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let individual = root["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]

        let reset = (root["billingCycleEnd"] as? String).flatMap(JSONLDateParsing.iso8601)
        return CursorUsageSummary(
            usedPercent: percentUsed(plan: plan),
            resetAt: reset,
            membershipType: root["membershipType"] as? String,
            autoPercentUsed: doubleValue(plan?["autoPercentUsed"]).map(clampPercent),
            apiPercentUsed: doubleValue(plan?["apiPercentUsed"]).map(clampPercent)
        )
    }

    /// Prefer the two independent allowances; the combined percentage is not a third pool.
    public func quotaWindows(observedAt: Date?, fallbackLabel: String? = nil) -> [QuotaWindow] {
        if let autoPercentUsed, let apiPercentUsed {
            return [
                quotaWindow(percent: autoPercentUsed, label: "Cursor models", bucket: "cursor_auto", at: observedAt),
                quotaWindow(percent: apiPercentUsed, label: "Other models", bucket: "cursor_api", at: observedAt)
            ]
        }
        guard let usedPercent else { return [] }
        return [quotaWindow(percent: usedPercent, label: fallbackLabel ?? membershipType, bucket: nil, at: observedAt)]
    }

    private func quotaWindow(percent: Double, label: String?, bucket: String?, at observedAt: Date?) -> QuotaWindow {
        QuotaWindow(providerID: .cursor, type: .monthly, used: percent, limit: 100,
                    remaining: 100 - percent, resetAt: resetAt, confidence: .providerReported,
                    source: "cursor.com/api/usage-summary", label: label, bucketKey: bucket, observedAt: observedAt)
    }

    private static func percentUsed(plan: [String: Any]?) -> Double? {
        guard let plan else { return nil }
        if let total = doubleValue(plan["totalPercentUsed"]) { return clampPercent(total) }

        let auto = doubleValue(plan["autoPercentUsed"])
        let api = doubleValue(plan["apiPercentUsed"])
        if let auto, let api { return clampPercent((auto + api) / 2) }
        if let auto { return clampPercent(auto) }
        if let api { return clampPercent(api) }

        if let used = doubleValue(plan["used"]), let limit = doubleValue(plan["limit"]), limit > 0 {
            return clampPercent(used / limit * 100)
        }
        return nil
    }

    private static func clampPercent(_ value: Double) -> Double { min(100, max(0, value)) }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String, let number = Double(string), number.isFinite { return number }
        return nil
    }
}
