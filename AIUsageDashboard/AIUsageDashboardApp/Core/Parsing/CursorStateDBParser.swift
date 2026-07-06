import Foundation
import SQLite3

public actor CursorStateDBParser {
    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage?
        public let lifetime: TokenUsage?
        public let dailyTotals: [Date: Int]
        public let warnings: [ProviderWarning]
    }

    private let fileManager: FileManager
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
    }

    public func parse(stateDatabaseURL: URL) async -> AggregateUsage {
        do {
            let tempDirectory = try temporaryCopyDirectory()
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let databaseCopyURL = tempDirectory.appendingPathComponent(stateDatabaseURL.lastPathComponent)
            try copyDatabase(from: stateDatabaseURL, to: databaseCopyURL)
            return try parseCopiedDatabase(at: databaseCopyURL)
        } catch {
            return Self.unavailable(warnings: [
                ProviderWarning(
                    message: "Cursor local state database could not be read: \(error.localizedDescription)",
                    level: .warning
                )
            ])
        }
    }

    private func temporaryCopyDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("TokeiCursorStateDB-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func copyDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        for suffix in ["-wal", "-shm"] {
            let sourceSidecar = URL(fileURLWithPath: sourceURL.path + suffix)
            guard fileManager.fileExists(atPath: sourceSidecar.path) else { continue }
            let destinationSidecar = URL(fileURLWithPath: destinationURL.path + suffix)
            try? fileManager.copyItem(at: sourceSidecar, to: destinationSidecar)
        }
    }

    private func parseCopiedDatabase(at url: URL) throws -> AggregateUsage {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { sqliteMessage($0) } ?? "unable to open copied Cursor state database"
            if let database { sqlite3_close(database) }
            throw SQLiteReadError(message: message)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, Self.usageRowsSQL, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteReadError(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let referenceDate = now()
        var windows = UsageWindows(calendar: calendar, referenceDate: referenceDate)
        var foundTokenMetrics = false

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let key = stringColumn(statement, index: 0),
                let value = dataColumn(statement, index: 1),
                let usage = datedTokenUsage(key: key, value: value)
            else {
                continue
            }

            foundTokenMetrics = true
            windows.accumulate(
                usage.tokenUsage,
                timestamp: usage.date,
                dailyTotal: usage.tokenUsage.totalTokens ?? 0
            )
        }

        guard foundTokenMetrics else {
            return Self.noLocalTokenMetrics()
        }

        let snapshot = windows.snapshot()
        return AggregateUsage(
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            lifetime: snapshot.lifetime,
            dailyTotals: snapshot.dailyTotals,
            warnings: []
        )
    }

    private func datedTokenUsage(key: String, value: Data) -> CursorDatedTokenUsage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: value) as? [String: Any],
            let tokenObject = tokenObject(in: object),
            let tokenUsage = tokenUsage(from: tokenObject)
        else {
            return nil
        }

        guard let date = date(from: object, tokenObject: tokenObject, key: key) else {
            return nil
        }

        return CursorDatedTokenUsage(date: date, tokenUsage: tokenUsage)
    }

    private func tokenObject(in object: [String: Any], depth: Int = 0) -> [String: Any]? {
        guard depth <= 2 else { return nil }
        if hasTokenComponent(in: object) {
            return object
        }

        for value in object.values {
            if let nested = value as? [String: Any],
               let match = tokenObject(in: nested, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func hasTokenComponent(in object: [String: Any]) -> Bool {
        intValue(for: Self.inputTokenKeys, in: object) != nil ||
            intValue(for: Self.outputTokenKeys, in: object) != nil ||
            intValue(for: Self.cacheReadTokenKeys, in: object) != nil ||
            intValue(for: Self.cacheCreationTokenKeys, in: object) != nil ||
            intValue(for: Self.reasoningTokenKeys, in: object) != nil
    }

    private func tokenUsage(from object: [String: Any]) -> TokenUsage? {
        let input = intValue(for: Self.inputTokenKeys, in: object)
        let output = intValue(for: Self.outputTokenKeys, in: object)
        let cacheRead = intValue(for: Self.cacheReadTokenKeys, in: object)
        let cacheCreation = intValue(for: Self.cacheCreationTokenKeys, in: object)
        let reasoning = intValue(for: Self.reasoningTokenKeys, in: object)

        guard [input, output, cacheRead, cacheCreation, reasoning].contains(where: { $0 != nil }) else {
            return nil
        }

        return TokenUsage(
            inputTokens: max(0, input ?? 0),
            outputTokens: max(0, output ?? 0),
            cacheReadTokens: max(0, cacheRead ?? 0),
            cacheCreationTokens: max(0, cacheCreation ?? 0),
            reasoningTokens: max(0, reasoning ?? 0),
            confidence: .localParsed
        )
    }

    private func date(from object: [String: Any], tokenObject: [String: Any], key: String) -> Date? {
        let dateString = stringValue(object["date"]) ??
            stringValue(object["day"]) ??
            stringValue(tokenObject["date"]) ??
            stringValue(tokenObject["day"]) ??
            dateSuffix(from: key)

        guard let dateString else { return nil }
        return date(fromDayString: dateString)
    }

    private func date(fromDayString dayString: String) -> Date? {
        let parts = dayString.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func dateSuffix(from key: String) -> String? {
        guard let match = key.range(
            of: #"\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(key[match])
    }

    private func intValue(for aliases: Set<String>, in object: [String: Any]) -> Int? {
        for (key, value) in object where aliases.contains(key.lowercased()) {
            return intValue(value)
        }
        return nil
    }

    private func intValue(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return nil
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func dataColumn(_ statement: OpaquePointer, index: Int32) -> Data? {
        let byteCount = sqlite3_column_bytes(statement, index)
        guard byteCount > 0, let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: bytes, count: Int(byteCount))
    }

    private func sqliteMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }

    private static func noLocalTokenMetrics() -> AggregateUsage {
        unavailable(warnings: [
            ProviderWarning(
                message: "Cursor token metrics were not found in the local state database",
                level: .info
            )
        ])
    }

    private static func unavailable(warnings: [ProviderWarning]) -> AggregateUsage {
        AggregateUsage(
            today: .unavailable,
            week: .unavailable,
            month: nil,
            lifetime: nil,
            dailyTotals: [:],
            warnings: warnings
        )
    }

    private static let usageRowsSQL = """
        SELECT key, value FROM ItemTable
        WHERE lower(key) NOT LIKE 'secret://%'
          AND lower(key) NOT LIKE 'cursorauth/%'
          AND lower(key) NOT LIKE '%accesstoken%'
          AND lower(key) NOT LIKE '%refreshtoken%'
          AND (
            lower(key) LIKE '%usage%'
            OR lower(key) LIKE '%quota%'
            OR lower(key) LIKE '%limit%'
            OR lower(key) LIKE '%token%'
            OR lower(key) LIKE '%meter%'
            OR lower(key) LIKE '%dailystats%'
          )
        """

    private static let inputTokenKeys: Set<String> = [
        "inputtokens",
        "input_tokens",
        "prompttokens",
        "prompt_tokens"
    ]
    private static let outputTokenKeys: Set<String> = [
        "outputtokens",
        "output_tokens",
        "completiontokens",
        "completion_tokens"
    ]
    private static let cacheReadTokenKeys: Set<String> = [
        "cachereadtokens",
        "cache_read_tokens",
        "cachedinputtokens",
        "cached_input_tokens",
        "cache_read_input_tokens"
    ]
    private static let cacheCreationTokenKeys: Set<String> = [
        "cachecreationtokens",
        "cache_creation_tokens",
        "cachewritetokens",
        "cache_write_tokens",
        "cache_creation_input_tokens"
    ]
    private static let reasoningTokenKeys: Set<String> = [
        "reasoningtokens",
        "reasoning_tokens",
        "reasoningoutputtokens",
        "reasoning_output_tokens"
    ]
}

private struct CursorDatedTokenUsage {
    let date: Date
    let tokenUsage: TokenUsage
}

private struct SQLiteReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
