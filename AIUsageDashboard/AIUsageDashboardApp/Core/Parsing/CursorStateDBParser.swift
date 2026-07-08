import Foundation
import SQLite3

public actor CursorStateDBParser {
    public struct OfflineState: Sendable {
        public let isAuthenticated: Bool
        public let membershipType: String?
        public let subscriptionStatus: String?
        public let email: String?
        public let acceptedLinesByDate: [Date: Int]
        public let warnings: [ProviderWarning]

        public init(
            isAuthenticated: Bool,
            membershipType: String? = nil,
            subscriptionStatus: String? = nil,
            email: String? = nil,
            acceptedLinesByDate: [Date: Int] = [:],
            warnings: [ProviderWarning] = []
        ) {
            self.isAuthenticated = isAuthenticated
            self.membershipType = membershipType
            self.subscriptionStatus = subscriptionStatus
            self.email = email
            self.acceptedLinesByDate = acceptedLinesByDate
            self.warnings = warnings
        }
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

    public func parse(stateDatabaseURL: URL) async -> OfflineState {
        do {
            let tempDirectory = try temporaryCopyDirectory()
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let databaseCopyURL = tempDirectory.appendingPathComponent(stateDatabaseURL.lastPathComponent)
            try copyDatabase(from: stateDatabaseURL, to: databaseCopyURL)
            return try parseCopiedDatabase(at: databaseCopyURL)
        } catch {
            return OfflineState(
                isAuthenticated: false,
                warnings: [
                    ProviderWarning(
                        message: "Cursor local state database could not be read: \(error.localizedDescription)",
                        level: .warning
                    )
                ]
            )
        }
    }

    /// Reads the JWT value for the network path. The value is returned to the caller
    /// and must leave the process only inside the WorkOS session cookie sent to
    /// `cursor.com` over TLS (`CursorSession` / `CursorUsageClientImpl`).
    public func readAccessToken(stateDatabaseURL: URL) async -> String? {
        do {
            let tempDirectory = try temporaryCopyDirectory()
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let databaseCopyURL = tempDirectory.appendingPathComponent(stateDatabaseURL.lastPathComponent)
            try copyDatabase(from: stateDatabaseURL, to: databaseCopyURL)
            return try readAccessTokenValue(at: databaseCopyURL)
        } catch {
            return nil
        }
    }

    // MARK: - Private helpers

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

    private func parseCopiedDatabase(at url: URL) throws -> OfflineState {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { sqliteMessage($0) } ?? "unable to open copied Cursor state database"
            if let database { sqlite3_close(database) }
            throw SQLiteReadError(message: message)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, Self.offlineStateSQL, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteReadError(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        var isAuthenticated = false
        var membershipType: String?
        var subscriptionStatus: String?
        var email: String?
        var acceptedLinesByDate: [Date: Int] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = stringColumn(statement, index: 0) else { continue }
            let value = dataColumn(statement, index: 1)

            switch key {
            case "cursorAuth/accessToken":
                if let data = value, let token = stringValue(from: data), !token.isEmpty {
                    isAuthenticated = true
                }
            case "cursorAuth/stripeMembershipType":
                membershipType = value.flatMap { stringValue(from: $0) }
            case "cursorAuth/stripeSubscriptionStatus":
                subscriptionStatus = value.flatMap { stringValue(from: $0) }
            case "cursorAuth/cachedEmail":
                email = value.flatMap { stringValue(from: $0) }
            default:
                if key.hasPrefix("aiCodeTracking.dailyStats.v1.5."),
                   let data = value,
                   let dateSuffix = dateSuffix(from: key),
                   let date = date(fromDayString: dateSuffix),
                   let acceptedLines = parseAcceptedLines(from: data) {
                    acceptedLinesByDate[date, default: 0] += acceptedLines
                }
            }
        }

        var warnings: [ProviderWarning] = []
        if membershipType != nil || subscriptionStatus != nil {
            let plan = [membershipType?.capitalized, subscriptionStatus.map { "(\($0))" }]
                .compactMap { $0 }
                .joined(separator: " ")
            warnings.append(ProviderWarning(message: "Plan: \(plan)", level: .info))
        }

        return OfflineState(
            isAuthenticated: isAuthenticated,
            membershipType: membershipType,
            subscriptionStatus: subscriptionStatus,
            email: email,
            acceptedLinesByDate: acceptedLinesByDate,
            warnings: warnings
        )
    }

    private func readAccessTokenValue(at url: URL) throws -> String? {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { sqliteMessage($0) } ?? "unable to open copied Cursor state database"
            if let database { sqlite3_close(database) }
            throw SQLiteReadError(message: message)
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, Self.accessTokenSQL, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw SQLiteReadError(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let data = dataColumn(statement, index: 0) else { return nil }
        let token = stringValue(from: data)
        return token?.isEmpty == false ? token : nil
    }

    private func stringValue(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data, options: .allowFragments),
           let string = json as? String {
            return string
        }
        if let string = String(data: data, encoding: .utf8) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func parseAcceptedLines(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let tabAccepted = intValue(json["tabAcceptedLines"])
        let composerAccepted = intValue(json["composerAcceptedLines"])
        guard tabAccepted != nil || composerAccepted != nil else { return nil }
        return (tabAccepted ?? 0) + (composerAccepted ?? 0)
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
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
        guard let match = key.range(of: #"\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) else {
            return nil
        }
        return String(key[match])
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
        guard let message = sqlite3_errmsg(database) else { return "unknown SQLite error" }
        return String(cString: message)
    }

    private static let offlineStateSQL = """
        SELECT key, value FROM ItemTable
        WHERE key = 'cursorAuth/stripeMembershipType'
           OR key = 'cursorAuth/stripeSubscriptionStatus'
           OR key = 'cursorAuth/cachedEmail'
           OR key = 'cursorAuth/accessToken'
           OR key LIKE 'aiCodeTracking.dailyStats.v1.5.%'
        """

    private static let accessTokenSQL = """
        SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'
        """
}

private struct SQLiteReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
