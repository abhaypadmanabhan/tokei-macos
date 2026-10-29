// Adapted from T3 Code: apps/server/src/provider/Drivers/antigravityUsageReader.ts (MIT).
import Foundation
import SQLite3

struct AntigravityConversationDatabase: Sendable {
    let records: [AntigravityConversationRecord]
    let models: [Int: String]

    private struct TimeSource { let own: Date?; let trajectory: Date?; let modified: Date }
    private struct Row { let index: Int; let message: AntigravityProtobuf }
    private enum ReadError: Error { case database }

    static func read(_ url: URL, modifiedAt: Date) throws -> Self {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database = handle else {
            if let handle { sqlite3_close(handle) }
            throw ReadError.database
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        guard sqlite3_exec(database, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw ReadError.database }
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        let hasGenerations = try hasTable("gen_metadata", database: database)
        let hasSteps = try hasTable("steps", database: database)
        guard hasGenerations || hasSteps else { throw ReadError.database }
        let trajectory = try trajectoryTimestamp(database)
        let generations = hasGenerations ? try rows("gen_metadata", column: "data", database: database) : []
        let steps = hasSteps ? try rows("steps", column: "metadata", database: database) : []
        var models: [Int: String] = [:]
        var generationRecords: [AntigravityConversationRecord] = []
        for row in generations {
            guard let generation = try row.message.message(1) else { throw AntigravityProtobuf.DecodeError.malformed }
            let model = try modelName(generation, display: 21, slug: 19)
            if let model, generation.number(3) > 0 { models[generation.number(3)] = model }
            let ownTime = try generation.message(9)?.message(4)?.timestamp
            generationRecords += try records(generation, usageField: 4, attempts: 17,
                model: model, time: TimeSource(own: ownTime, trajectory: trajectory, modified: modifiedAt))
        }
        var stepRecords: [AntigravityConversationRecord] = []
        for row in steps {
            let modelMessage = try row.message.message(24)
            let model = try modelMessage.flatMap { try modelName($0, display: 8, slug: 12) }
            let ownTime = try row.message.message(8)?.timestamp ?? row.message.message(1)?.timestamp
            stepRecords += try records(row.message, usageField: 9, attempts: 28,
                model: model, time: TimeSource(own: ownTime, trajectory: trajectory, modified: modifiedAt))
        }
        return Self(records: stepRecords + generationRecords, models: models)
    }

    private static func modelName(_ message: AntigravityProtobuf, display: Int, slug: Int) throws -> String? {
        try AntigravityConversationRecord.normalized(message.text(display))
            ?? AntigravityConversationRecord.normalized(message.text(slug))
    }

    private static func records(
        _ message: AntigravityProtobuf, usageField: Int, attempts: Int,
        model: String?, time: TimeSource
    ) throws -> [AntigravityConversationRecord] {
        var usages = try message.message(usageField).map { [$0] } ?? []
        usages += try message.messages(attempts).compactMap { try $0.message(2) }
        return try usages.compactMap { usage in
            let input = usage.number(2)
            let cached = usage.number(5)
            let creation = usage.number(4)
            let reasoning = usage.number(9)
            let output = max(usage.number(3), reasoning + usage.number(10))
            guard input + cached + creation + output > 0 else { return nil }
            let keys = try [11, 12, 7].compactMap { field -> String? in
                try usage.text(field).map { "antigravity:\(field):\($0)" }
            }
            return AntigravityConversationRecord(modelID: usage.number(1), model: model,
                timestamp: time.own ?? time.trajectory ?? time.modified,
                timestampQuality: time.own != nil ? 2 : (time.trajectory != nil ? 1 : 0), keys: keys,
                input: input, cached: cached, creation: creation, output: output, reasoning: min(output, reasoning))
        }
    }

    private static func hasTable(_ name: String, database: OpaquePointer) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(name)'"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw ReadError.database }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw ReadError.database }
        return result == SQLITE_ROW
    }

    private static func trajectoryTimestamp(_ database: OpaquePointer) throws -> Date? {
        guard try hasTable("trajectory_metadata_blob", database: database) else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT data FROM trajectory_metadata_blob", -1,
                                 &statement, nil) == SQLITE_OK else { throw ReadError.database }
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw ReadError.database }
            if sqlite3_column_type(statement, 0) == SQLITE_NULL { continue }
            let message = try AntigravityProtobuf(blob(statement, column: 0))
            if let timestamp = try message.message(2)?.timestamp { return timestamp }
        }
    }

    private static func rows(_ table: String, column: String, database: OpaquePointer) throws -> [Row] {
        var result: [Row] = []
        var rowID = Int64.min
        let pageSize = table == "gen_metadata" ? 1 : 64
        while true {
            var statement: OpaquePointer?
            let sql = "SELECT rowid, idx, \(column) FROM \(table) WHERE rowid > ? ORDER BY rowid LIMIT \(pageSize)"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw ReadError.database }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, rowID)
            var count = 0
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW, sqlite3_column_type(statement, 1) == SQLITE_INTEGER else {
                    throw ReadError.database
                }
                count += 1
                rowID = sqlite3_column_int64(statement, 0)
                if sqlite3_column_type(statement, 2) == SQLITE_NULL { continue }
                result.append(Row(index: Int(sqlite3_column_int64(statement, 1)),
                                  message: try AntigravityProtobuf(blob(statement, column: 2))))
            }
            if count < pageSize { break }
        }
        return result.sorted { $0.index < $1.index }
    }

    private static func blob(_ statement: OpaquePointer?, column: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, column) else { throw ReadError.database }
        return Data(bytes: bytes, count: count)
    }
}
