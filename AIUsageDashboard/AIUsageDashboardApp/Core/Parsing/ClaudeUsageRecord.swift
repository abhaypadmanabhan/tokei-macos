import Foundation

/// A single usage record extracted from a Claude JSONL log line.
public struct ClaudeUsageRecord: Sendable, Equatable {
    public let messageID: String?
    public let requestID: String?
    public let sessionID: String?
    public let uuid: String?
    public let timestamp: Date?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int

    public init(
        messageID: String?,
        requestID: String?,
        sessionID: String?,
        uuid: String?,
        timestamp: Date?,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int
    ) {
        self.messageID = messageID
        self.requestID = requestID
        self.sessionID = sessionID
        self.uuid = uuid
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    public var dedupeKey: String? {
        messageID ?? requestID ?? uuid
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    public func toTokenUsage() -> TokenUsage {
        TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadInputTokens,
            cacheCreationTokens: cacheCreationInputTokens,
            confidence: .localParsed
        )
    }
}
