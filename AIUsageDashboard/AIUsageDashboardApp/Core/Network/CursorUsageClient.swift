import Foundation

/// Reads Cursor's web dashboard usage. Both calls authenticate with the WorkOS
/// session cookie (`CursorSession`) — never a Bearer token — matching the paths
/// the Cursor dashboard itself uses:
/// - tokens: `GET cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens`
///   → a per-event CSV (real input / cache / output split + cost + timestamp).
/// - quota:  `GET cursor.com/api/usage-summary` → plan utilisation %.
///
/// The client is a thin transport: it returns the raw payloads so the pure
/// parsers below (`CursorUsageCSV`, `CursorUsageSummary`) stay trivially testable.
public protocol CursorUsageClient: Sendable {
    /// Raw CSV body of the token-usage export.
    func fetchUsageEventsCSV(cookie: String) async throws -> String
    /// Raw JSON body of the usage summary.
    func fetchUsageSummary(cookie: String) async throws -> Data
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

    public func fetchUsageEventsCSV(cookie: String) async throws -> String {
        let data = try await get(Self.usageEventsCSVURL, cookie: cookie, accept: "text/csv, */*")
        guard let text = String(data: data, encoding: .utf8) else {
            throw CursorUsageError.unexpectedResponse
        }
        return text
    }

    public func fetchUsageSummary(cookie: String) async throws -> Data {
        try await get(Self.usageSummaryURL, cookie: cookie, accept: "application/json")
    }

    private func get(_ url: URL, cookie: String, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        // Send our explicit Cookie header verbatim; don't let URLSession's cookie
        // storage override or strip it.
        request.httpShouldHandleCookies = false
        // SECURITY: the session cookie leaves the process only as this header, over TLS.
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://www.cursor.com/settings", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CursorUsageError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private static let usageEventsCSVURL = URL(
        string: "https://cursor.com/api/dashboard/export-usage-events-csv?strategy=tokens"
    )!
    private static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    // A desktop browser UA — the dashboard endpoints reject an empty/curl agent.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

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
    private static let requiredColumns = [
        "Date", "Model", "Input (w/ Cache Write)", "Input (w/o Cache Write)",
        "Cache Read", "Output Tokens", "Cost"
    ]

    public static func parseEvents(_ csv: String) -> [CursorUsageEvent] {
        var rows = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard !rows.isEmpty else { return [] }

        let header = splitFields(rows.removeFirst())
        var index: [String: Int] = [:]
        for (position, name) in header.enumerated() where index[name] == nil {
            index[name] = position
        }
        guard requiredColumns.allSatisfy({ index[$0] != nil }) else { return [] }

        func field(_ fields: [String], _ column: String) -> String? {
            guard let position = index[column], position < fields.count else { return nil }
            return fields[position]
        }

        return rows.compactMap { row -> CursorUsageEvent? in
            let fields = splitFields(row)
            guard let dateString = field(fields, "Date"), let date = parseDate(dateString) else {
                return nil
            }
            let inputWithout = intValue(field(fields, "Input (w/o Cache Write)"))
            let inputWith = intValue(field(fields, "Input (w/ Cache Write)"))
            let cacheWrite = max(0, inputWith - inputWithout)
            let cacheRead = intValue(field(fields, "Cache Read"))
            let output = intValue(field(fields, "Output Tokens"))

            // Drop rows with no usage at all; keep non-billable rows (they are real usage).
            let total = inputWithout + cacheWrite + cacheRead + output
            guard total > 0 || inputWithout > 0 || output > 0 else { return nil }

            return CursorUsageEvent(
                date: date,
                model: field(fields, "Model") ?? "",
                inputTokens: inputWithout,
                cacheWriteTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                outputTokens: output,
                cost: floatValue(field(fields, "Cost"))
            )
        }
    }

    /// RFC4180-ish field split: honours double-quoted fields (which may contain
    /// commas) and `""` escapes. Trims surrounding whitespace on unquoted fields.
    static func splitFields(_ line: String) -> [String] {
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
        if let date = JSONLDateParsing.fractional.date(from: trimmed) { return date }
        if let date = JSONLDateParsing.standard.date(from: trimmed) { return date }
        return dayOnlyFormatter.date(from: trimmed)
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

    public init(usedPercent: Double?, resetAt: Date?, membershipType: String?) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.membershipType = membershipType
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

        let reset = (root["billingCycleEnd"] as? String).flatMap(parseISODate)
        return CursorUsageSummary(
            usedPercent: percentUsed(plan: plan),
            resetAt: reset,
            membershipType: root["membershipType"] as? String
        )
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
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func parseISODate(_ string: String) -> Date? {
        if let date = JSONLDateParsing.fractional.date(from: string) { return date }
        return JSONLDateParsing.standard.date(from: string)
    }
}
