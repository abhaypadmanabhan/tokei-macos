import Foundation
import SQLite3

public actor OpencodeStoreParser {
    public enum SourceKind: Sendable, Equatable {
        case sqliteDatabase
        case jsonFiles
        case none
    }

    public struct AggregateUsage: Sendable {
        public let today: TokenUsage
        public let week: TokenUsage
        public let month: TokenUsage
        public let lifetime: TokenUsage
        public let dailyTotals: [Date: Int]
        public let totalCost: Double
        public let sourceKind: SourceKind
        public let warnings: [ProviderWarning]
    }

    private struct ParsedMessage: Sendable {
        let usage: TokenUsage
        let timestamp: Date?
        let dailyTotal: Int
        let cost: Double
    }

    private struct DatabaseRead: Sendable {
        let rowCount: Int
        let malformedCount: Int
        let messages: [ParsedMessage]
    }

    private struct JSONRead: Sendable {
        let fileCount: Int
        let malformedCount: Int
        let messages: [ParsedMessage]
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

    public func parse(rootDirectory: URL) async -> AggregateUsage {
        var warnings: [ProviderWarning] = []
        let databaseURL = rootDirectory.appendingPathComponent("opencode.db")

        if fileManager.fileExists(atPath: databaseURL.path) {
            do {
                let databaseRead = try readDatabase(at: databaseURL)
                if databaseRead.rowCount > 0 {
                    warnings.append(contentsOf: malformedWarnings(
                        count: databaseRead.malformedCount,
                        source: databaseURL.lastPathComponent
                    ))
                    return aggregate(
                        messages: databaseRead.messages,
                        sourceKind: .sqliteDatabase,
                        warnings: warnings
                    )
                }
            } catch {
                warnings.append(ProviderWarning(
                    message: "opencode database could not be read: \(error.localizedDescription)",
                    level: .warning
                ))
            }
        }

        do {
            let jsonRead = try readJSONMessages(rootDirectory: rootDirectory)
            warnings.append(contentsOf: malformedWarnings(
                count: jsonRead.malformedCount,
                source: "opencode JSON message file(s)"
            ))
            let sourceKind: SourceKind = jsonRead.fileCount > 0 ? .jsonFiles : .none
            return aggregate(messages: jsonRead.messages, sourceKind: sourceKind, warnings: warnings)
        } catch {
            warnings.append(ProviderWarning(
                message: "opencode JSON messages could not be read: \(error.localizedDescription)",
                level: .warning
            ))
            return aggregate(messages: [], sourceKind: .none, warnings: warnings)
        }
    }

    public func discoverLogSources(rootDirectory: URL) async throws -> [LogSource] {
        let databaseURL = rootDirectory.appendingPathComponent("opencode.db")
        if fileManager.fileExists(atPath: databaseURL.path),
           (try? databaseRowCount(at: databaseURL)) ?? 0 > 0 {
            return [LogSource(providerID: .opencode, url: databaseURL)]
        }

        return try discoverJSONSources(rootDirectory: rootDirectory)
    }

    private func aggregate(
        messages: [ParsedMessage],
        sourceKind: SourceKind,
        warnings: [ProviderWarning]
    ) -> AggregateUsage {
        var windows = UsageWindows(calendar: calendar, referenceDate: now())
        var totalCost = 0.0

        for message in messages {
            windows.accumulate(message.usage, timestamp: message.timestamp, dailyTotal: message.dailyTotal)
            totalCost += message.cost
        }

        let snapshot = windows.snapshot()
        return AggregateUsage(
            today: snapshot.today,
            week: snapshot.week,
            month: snapshot.month,
            lifetime: snapshot.lifetime,
            dailyTotals: snapshot.dailyTotals,
            totalCost: totalCost,
            sourceKind: sourceKind,
            warnings: warnings
        )
    }

    private func malformedWarnings(count: Int, source: String) -> [ProviderWarning] {
        guard count > 0 else { return [] }
        return [ProviderWarning(
            message: "\(source): \(count) malformed opencode message(s) skipped",
            level: .warning
        )]
    }

    // MARK: - SQLite

    private func readDatabase(at url: URL) throws -> DatabaseRead {
        let tempDirectory = try temporaryCopyDirectory()
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let databaseCopyURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
        try copyDatabase(from: url, to: databaseCopyURL)
        return try readCopiedDatabase(at: databaseCopyURL)
    }

    private func databaseRowCount(at url: URL) throws -> Int {
        let tempDirectory = try temporaryCopyDirectory()
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let databaseCopyURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
        try copyDatabase(from: url, to: databaseCopyURL)
        return try readRowCount(at: databaseCopyURL)
    }

    private func temporaryCopyDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("TokeiOpencodeStore-\(UUID().uuidString)", isDirectory: true)
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

    private func readCopiedDatabase(at url: URL) throws -> DatabaseRead {
        let database = try openDatabase(at: url)
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, Self.messagesSQL, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw OpencodeSQLiteReadError(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        var rowCount = 0
        var malformedCount = 0
        var messages: [ParsedMessage] = []

        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                rowCount += 1
                guard let dataText = stringColumn(statement, index: 0) else {
                    malformedCount += 1
                    continue
                }
                let fallbackCreatedMillis = int64Column(statement, index: 1)
                switch parseMessage(dataText, fallbackCreatedMillis: fallbackCreatedMillis) {
                case .message(let message):
                    messages.append(message)
                case .skipped:
                    break
                case .malformed:
                    malformedCount += 1
                }
            case SQLITE_DONE:
                return DatabaseRead(rowCount: rowCount, malformedCount: malformedCount, messages: messages)
            default:
                throw OpencodeSQLiteReadError(message: sqliteMessage(database))
            }
        }
    }

    private func readRowCount(at url: URL) throws -> Int {
        let database = try openDatabase(at: url)
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, Self.rowCountSQL, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw OpencodeSQLiteReadError(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func openDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { sqliteMessage($0) } ?? "unable to open copied opencode database"
            if let database { sqlite3_close(database) }
            throw OpencodeSQLiteReadError(message: message)
        }
        return database
    }

    // MARK: - JSON fallback

    private func readJSONMessages(rootDirectory: URL) throws -> JSONRead {
        let sources = try discoverJSONSources(rootDirectory: rootDirectory)
        var malformedCount = 0
        var messages: [ParsedMessage] = []

        for source in sources {
            do {
                let dataText = try String(contentsOf: source.url, encoding: .utf8)
                switch parseMessage(dataText, fallbackCreatedMillis: nil) {
                case .message(let message):
                    messages.append(message)
                case .skipped:
                    break
                case .malformed:
                    malformedCount += 1
                }
            } catch {
                malformedCount += 1
            }
        }

        return JSONRead(fileCount: sources.count, malformedCount: malformedCount, messages: messages)
    }

    private func discoverJSONSources(rootDirectory: URL) throws -> [LogSource] {
        let messageRoot = rootDirectory.appendingPathComponent("storage/message", isDirectory: true)
        guard fileManager.fileExists(atPath: messageRoot.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: messageRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [LogSource] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "json" else { continue }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            let sessionID = file.deletingLastPathComponent().lastPathComponent
            sources.append(LogSource(
                providerID: .opencode,
                url: file,
                sessionID: sessionID.isEmpty ? nil : sessionID,
                lastModified: values?.contentModificationDate
            ))
        }

        return sources.sorted { $0.url.path < $1.url.path }
    }

    // MARK: - Message parsing

    private enum MessageParseOutcome {
        case message(ParsedMessage)
        case skipped
        case malformed
    }

    private func parseMessage(_ dataText: String, fallbackCreatedMillis: Int64?) -> MessageParseOutcome {
        guard let data = dataText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }

        guard json["role"] as? String == "assistant" else {
            return .skipped
        }
        guard let tokens = json["tokens"] as? [String: Any] else {
            return .skipped
        }

        let cache = tokens["cache"] as? [String: Any]
        let usage = TokenUsage(
            inputTokens: intValue(tokens["input"]) ?? 0,
            outputTokens: intValue(tokens["output"]) ?? 0,
            cacheReadTokens: intValue(cache?["read"]) ?? 0,
            cacheCreationTokens: intValue(cache?["write"]) ?? 0,
            reasoningTokens: intValue(tokens["reasoning"]) ?? 0,
            confidence: .localParsed
        )

        return .message(ParsedMessage(
            usage: usage,
            timestamp: createdDate(from: json, fallbackCreatedMillis: fallbackCreatedMillis),
            dailyTotal: usage.totalTokens ?? 0,
            cost: doubleValue(json["cost"]) ?? 0
        ))
    }

    private func createdDate(from json: [String: Any], fallbackCreatedMillis: Int64?) -> Date? {
        if let time = json["time"] as? [String: Any],
           let created = doubleValue(time["created"]) {
            return date(fromEpochValue: created)
        }
        if let fallbackCreatedMillis {
            return date(fromEpochValue: Double(fallbackCreatedMillis))
        }
        return nil
    }

    private func date(fromEpochValue value: Double) -> Date {
        let seconds = abs(value) >= 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(clamping: int64) }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let int64 = value as? Int64 { return Double(int64) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func int64Column(_ statement: OpaquePointer, index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func sqliteMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else { return "unknown SQLite error" }
        return String(cString: message)
    }

    private static let messagesSQL = """
        SELECT data, time_created FROM message
        ORDER BY time_created, id
        """

    private static let rowCountSQL = """
        SELECT COUNT(*) FROM message
        """
}

private struct OpencodeSQLiteReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
