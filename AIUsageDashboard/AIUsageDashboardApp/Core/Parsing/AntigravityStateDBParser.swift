import Foundation
import SQLite3

public actor AntigravityStateDBParser {
    public struct ParsedState: Sendable {
        public let planName: String?
        public let availableCredits: Int?
        public let minimumCreditAmountForUsage: Int?
        public let rawQuotaValues: [Int: UInt64]
        public let warnings: [ProviderWarning]

        public init(
            planName: String? = nil,
            availableCredits: Int? = nil,
            minimumCreditAmountForUsage: Int? = nil,
            rawQuotaValues: [Int: UInt64] = [:],
            warnings: [ProviderWarning] = []
        ) {
            self.planName = planName
            self.availableCredits = availableCredits
            self.minimumCreditAmountForUsage = minimumCreditAmountForUsage
            self.rawQuotaValues = rawQuotaValues
            self.warnings = warnings
        }
    }

    private struct UserStatusFields {
        let planName: String?
        let rawQuotaValues: [Int: UInt64]
    }

    private struct ModelCreditFields {
        let availableCredits: Int?
        let minimumCreditAmountForUsage: Int?
    }

    private let fileManager: FileManager
    private let protobufReader: MiniProtobufReader

    public init(
        fileManager: FileManager = .default,
        protobufReader: MiniProtobufReader = .init()
    ) {
        self.fileManager = fileManager
        self.protobufReader = protobufReader
    }

    public func parse(stateDatabaseURL: URL) async -> ParsedState {
        do {
            let tempDirectory = try temporaryCopyDirectory()
            defer { try? fileManager.removeItem(at: tempDirectory) }

            let databaseCopyURL = tempDirectory.appendingPathComponent(stateDatabaseURL.lastPathComponent)
            try copyDatabase(from: stateDatabaseURL, to: databaseCopyURL)
            return try parseCopiedDatabase(at: databaseCopyURL)
        } catch {
            return ParsedState(warnings: [
                ProviderWarning(
                    message: "Antigravity local state database could not be read: \(error.localizedDescription)",
                    level: .warning
                )
            ])
        }
    }

    private func temporaryCopyDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("TokeiAntigravityStateDB-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func copyDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        try SQLiteSidecarCopy.copyDatabase(from: sourceURL, to: destinationURL, using: fileManager)
    }

    private func parseCopiedDatabase(at url: URL) throws -> ParsedState {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { sqliteMessage($0) } ?? "unable to open copied Antigravity state database"
            if let database { sqlite3_close(database) }
            throw AntigravitySQLiteReadError(message: message)
        }
        defer { sqlite3_close(database) }

        var warnings: [ProviderWarning] = []
        let userStatus = parseUserStatus(base64: try readAuthStatusProtoBase64(database: database), warnings: &warnings)
        let modelCredits = parseModelCredits(base64: try readModelCreditsBase64(database: database), warnings: &warnings)

        return ParsedState(
            planName: userStatus.planName,
            availableCredits: modelCredits.availableCredits,
            minimumCreditAmountForUsage: modelCredits.minimumCreditAmountForUsage,
            rawQuotaValues: userStatus.rawQuotaValues,
            warnings: warnings
        )
    }

    private func readAuthStatusProtoBase64(database: OpaquePointer) throws -> String? {
        try readSingleText(
            database: database,
            sql: """
                SELECT json_extract(CAST(value AS TEXT), '$.userStatusProtoBinaryBase64')
                FROM ItemTable
                WHERE key = 'antigravityAuthStatus'
                LIMIT 1
                """
        )
    }

    private func readModelCreditsBase64(database: OpaquePointer) throws -> String? {
        try readSingleText(
            database: database,
            sql: """
                SELECT value
                FROM ItemTable
                WHERE key = 'antigravityUnifiedStateSync.modelCredits'
                LIMIT 1
                """
        )
    }

    private func readSingleText(database: OpaquePointer, sql: String) throws -> String? {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw AntigravitySQLiteReadError(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            guard sqlite3_column_type(statement, 0) != SQLITE_NULL,
                  let value = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return String(cString: value)
        }
        guard stepResult == SQLITE_DONE else {
            throw AntigravitySQLiteReadError(message: sqliteMessage(database))
        }
        return nil
    }

    private func parseUserStatus(
        base64: String?,
        warnings: inout [ProviderWarning]
    ) -> UserStatusFields {
        guard let base64, let data = Data(base64Encoded: base64) else {
            warnings.append(ProviderWarning(
                message: "Antigravity user status protobuf was not found in local state",
                level: .info
            ))
            return UserStatusFields(planName: nil, rawQuotaValues: [:])
        }

        let fields = protobufReader.parse(data)
        guard
            let statusFields = fields.first(number: 13)?.nestedFields,
            let quotaFields = statusFields.first(number: 1)?.nestedFields
        else {
            warnings.append(ProviderWarning(
                message: "Antigravity user status protobuf did not contain the expected quota branch",
                level: .warning
            ))
            return UserStatusFields(planName: nil, rawQuotaValues: [:])
        }

        let planName = quotaFields.first(number: 2)?.utf8String
        var rawQuotaValues: [Int: UInt64] = [:]
        for fieldNumber in [7, 8, 12, 13, 14] {
            if let value = quotaFields.first(number: fieldNumber)?.varintValue {
                rawQuotaValues[fieldNumber] = value
            }
        }

        return UserStatusFields(planName: planName, rawQuotaValues: rawQuotaValues)
    }

    private func parseModelCredits(
        base64: String?,
        warnings: inout [ProviderWarning]
    ) -> ModelCreditFields {
        guard let base64, let data = Data(base64Encoded: base64) else {
            warnings.append(ProviderWarning(
                message: "Antigravity model credits protobuf was not found in local state",
                level: .info
            ))
            return ModelCreditFields(availableCredits: nil, minimumCreditAmountForUsage: nil)
        }

        let fields = protobufReader.parse(data)
        var availableCredits: Int?
        var minimumCreditAmountForUsage: Int?

        for entry in fields.filter(number: 1) {
            guard let entryFields = entry.nestedFields,
                  let keyName = entryFields.first(number: 1)?.utf8String,
                  let encodedCredit = entryFields.first(number: 2)?
                    .nestedFields?
                    .first(number: 1)?
                    .utf8String,
                  let innerData = Data(base64Encoded: encodedCredit),
                  let creditValue = protobufReader.parse(innerData).first(number: 2)?.varintValue
            else {
                continue
            }

            switch keyName {
            case "availableCreditsSentinelKey":
                availableCredits = Int(clamping: creditValue)
            case "minimumCreditAmountForUsageKey":
                minimumCreditAmountForUsage = Int(clamping: creditValue)
            default:
                continue
            }
        }

        if availableCredits == nil || minimumCreditAmountForUsage == nil {
            warnings.append(ProviderWarning(
                message: "Antigravity model credits protobuf did not contain all expected credit keys",
                level: .warning
            ))
        }

        return ModelCreditFields(
            availableCredits: availableCredits,
            minimumCreditAmountForUsage: minimumCreditAmountForUsage
        )
    }

    private func sqliteMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }
}

private extension Array where Element == MiniProtobufReader.Field {
    func first(number: Int) -> MiniProtobufReader.Field? {
        first { $0.number == number }
    }

    func filter(number: Int) -> [MiniProtobufReader.Field] {
        filter { $0.number == number }
    }
}

private extension MiniProtobufReader.Field {
    var varintValue: UInt64? {
        guard case .varint(let value) = value else { return nil }
        return value
    }

    var nestedFields: [MiniProtobufReader.Field]? {
        guard case .lengthDelimited(_, let nestedFields) = value else { return nil }
        return nestedFields
    }

    var utf8String: String? {
        guard case .lengthDelimited(let data, _) = value else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct AntigravitySQLiteReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
