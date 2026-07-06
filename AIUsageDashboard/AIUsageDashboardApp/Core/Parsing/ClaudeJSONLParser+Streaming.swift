import Foundation

extension ClaudeJSONLParser {
    /// Streams a JSONL file line-by-line using URL.lines. Never loads the entire file into memory.
    func parseFile(at url: URL) async throws -> [ClaudeUsageRecord] {
        var records: [ClaudeUsageRecord] = []
        for try await line in url.lines {
            guard let data = line.data(using: .utf8) else { continue }
            if let record = try? parseLine(data) {
                records.append(record)
            }
        }
        return records
    }

    func parseLine(_ data: Data) throws -> ClaudeUsageRecord? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let usage = json["usage"] as? [String: Any]
            ?? (json["message"] as? [String: Any])?["usage"] as? [String: Any]
            ?? json

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0

        let messageID = json["message_id"] as? String ?? json["id"] as? String
        let requestID = json["request_id"] as? String
        let sessionID = json["session_id"] as? String

        let timestamp: Date?
        if let ts = json["timestamp"] as? TimeInterval {
            timestamp = Date(timeIntervalSince1970: ts)
        } else if let tsString = json["timestamp"] as? String, let date = ISO8601DateFormatter().date(from: tsString) {
            timestamp = date
        } else {
            timestamp = nil
        }

        return ClaudeUsageRecord(
            messageID: messageID,
            requestID: requestID,
            sessionID: sessionID,
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadInputTokens: cacheRead,
            cacheCreationInputTokens: cacheCreate
        )
    }
}

