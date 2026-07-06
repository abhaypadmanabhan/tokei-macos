import Foundation

enum LineParseOutcome: Sendable {
    case usage(ClaudeUsageRecord)
    case skipped
    case malformed
}

extension ClaudeJSONLParser {
    /// Streams a JSONL file line-by-line using URL.lines. Never loads the entire file into memory.
    func parseFile(at url: URL, onRecord: (ClaudeUsageRecord) -> Void) async throws -> Int {
        var malformedCount = 0
        for try await line in url.lines {
            guard let data = line.data(using: .utf8) else { continue }
            switch parseLine(data) {
            case .usage(let record):
                onRecord(record)
            case .skipped:
                break
            case .malformed:
                malformedCount += 1
            }
        }
        return malformedCount
    }

    func parseLine(_ data: Data) -> LineParseOutcome {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed
        }

        guard let usage = extractUsage(from: json) else {
            return .skipped
        }

        let message = json["message"] as? [String: Any]
        let messageID = message?["id"] as? String ?? json["message_id"] as? String
        let requestID = json["requestId"] as? String ?? json["request_id"] as? String
        let sessionID = json["sessionId"] as? String ?? json["session_id"] as? String
        let uuid = json["uuid"] as? String

        let record = ClaudeUsageRecord(
            messageID: messageID,
            requestID: requestID,
            sessionID: sessionID,
            uuid: uuid,
            timestamp: JSONLDateParsing.parseTimestamp(from: json),
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
        )
        return .usage(record)
    }

    private func extractUsage(from json: [String: Any]) -> [String: Any]? {
        if let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any] {
            return usage
        }
        if let usage = json["usage"] as? [String: Any],
           usage.keys.contains(where: { $0.hasSuffix("_tokens") }) {
            return usage
        }
        return nil
    }
}
