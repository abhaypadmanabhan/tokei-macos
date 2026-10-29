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
        let accessToken: String?

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
            self.accessToken = nil
        }

        init(
            isAuthenticated: Bool,
            membershipType: String?,
            subscriptionStatus: String?,
            email: String?,
            acceptedLinesByDate: [Date: Int],
            warnings: [ProviderWarning],
            accessToken: String?
        ) {
            self.isAuthenticated = isAuthenticated
            self.membershipType = membershipType
            self.subscriptionStatus = subscriptionStatus
            self.email = email
            self.acceptedLinesByDate = acceptedLinesByDate
            self.warnings = warnings
            self.accessToken = accessToken
        }

        /// Display plan label composed from the structured membership/subscription
        /// fields (e.g. "Pro (active)"), or nil when neither is present. The "Plan:"
        /// info warning is built from this — callers read it directly rather than
        /// re-parsing the warning string.
        public var planLabel: String? {
            Self.composePlanLabel(membershipType: membershipType, subscriptionStatus: subscriptionStatus)
        }

        static func composePlanLabel(membershipType: String?, subscriptionStatus: String?) -> String? {
            guard membershipType != nil || subscriptionStatus != nil else { return nil }
            return [membershipType?.capitalized, subscriptionStatus.map { "(\($0))" }]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    private let fileManager: FileManager
    private let calendar: Calendar
    private let copyDatabase: @Sendable (URL, URL) throws -> Void
    private var cached: (fingerprint: CursorDatabaseFingerprint, state: OfflineState)?

    public init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        copyDatabase: (@Sendable (URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.copyDatabase = copyDatabase ?? { source, destination in
            try SQLiteSidecarCopy.copyDatabase(from: source, to: destination, using: fileManager)
        }
        _ = now // Kept for source compatibility with the public initializer.
    }

    public func parse(stateDatabaseURL: URL) async -> OfflineState {
        let fingerprint = CursorDatabaseFingerprint(url: stateDatabaseURL, fileManager: fileManager)
        if let fingerprint, let cached, cached.fingerprint == fingerprint { return cached.state }
        cached = nil
        do {
            let tempDirectory = try temporaryCopyDirectory()
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let databaseCopyURL = tempDirectory.appendingPathComponent(stateDatabaseURL.lastPathComponent)
            try copyDatabase(stateDatabaseURL, databaseCopyURL)
            let state = try parseCopiedDatabase(at: databaseCopyURL)
            // A write during backup must trigger another scan, not bless a stale stamp.
            if let fingerprint,
               fingerprint == CursorDatabaseFingerprint(url: stateDatabaseURL, fileManager: fileManager) {
                cached = (fingerprint, state)
            }
            return state
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
        await parse(stateDatabaseURL: stateDatabaseURL).accessToken
    }

    // MARK: - Private helpers

    private func temporaryCopyDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("TokeiCursorStateDB-\(UUID().uuidString)", isDirectory: true)
        try SQLiteSidecarCopy.createPrivateSnapshotDirectory(at: directory, using: fileManager)
        return directory
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
        var accessToken: String?
        var acceptedLinesByDate: [Date: Int] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = stringColumn(statement, index: 0) else { continue }
            let value = dataColumn(statement, index: 1)

            switch key {
            case "cursorAuth/accessToken":
                if let data = value, let token = stringValue(from: data), !token.isEmpty {
                    isAuthenticated = true
                    accessToken = token
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
        if let plan = OfflineState.composePlanLabel(
            membershipType: membershipType, subscriptionStatus: subscriptionStatus
        ) {
            warnings.append(ProviderWarning(message: "Plan: \(plan)", level: .info))
        }

        return OfflineState(
            isAuthenticated: isAuthenticated,
            membershipType: membershipType,
            subscriptionStatus: subscriptionStatus,
            email: email,
            acceptedLinesByDate: acceptedLinesByDate,
            warnings: warnings,
            accessToken: accessToken
        )
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

}

private struct CursorDatabaseFingerprint: Equatable {
    let path: String
    let database: Stamp
    let wal: Stamp?
    let journal: Stamp?

    init?(url: URL, fileManager: FileManager) {
        guard let database = Stamp(url: url, fileManager: fileManager) else { return nil }
        path = url.path
        self.database = database
        wal = Stamp(url: URL(fileURLWithPath: url.path + "-wal"), fileManager: fileManager)
        journal = Stamp(url: URL(fileURLWithPath: url.path + "-journal"), fileManager: fileManager)
    }

    struct Stamp: Equatable {
        let size: UInt64
        let modified: Date
        let fileNumber: UInt64

        init?(url: URL, fileManager: FileManager) {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date,
                  let fileNumber = attributes[.systemFileNumber] as? NSNumber else { return nil }
            self.size = size.uint64Value
            self.modified = modified
            self.fileNumber = fileNumber.uint64Value
        }
    }
}

private struct SQLiteReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
