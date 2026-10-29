import Foundation

/// A single usage record extracted from a Claude JSONL log line.
public struct ClaudeUsageRecord: Sendable, Equatable {
    public let messageID: String?
    public let requestID: String?
    public let sessionID: String?
    public let uuid: String?
    public let timestamp: Date?
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreation1hTokens: Int?
    public let cacheCreationInputTokens: Int
    /// Start of the record's day and hour in the parser's calendar, computed once at parse
    /// time. Allocation re-runs over every cached record on each refresh; recomputing these
    /// there was about half of its CPU. `nil` when built without them (then derived on use).
    public let day: Date?
    public let hour: Date?

    public init(
        messageID: String?,
        requestID: String?,
        sessionID: String?,
        uuid: String?,
        timestamp: Date?,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheCreation1hTokens: Int? = nil,
        model: String = "unknown",
        day: Date? = nil,
        hour: Date? = nil
    ) {
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.model = model
        self.day = day
        self.hour = hour
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
        TokenArithmetic.sum([
            inputTokens,
            outputTokens,
            cacheReadInputTokens,
            cacheCreationInputTokens
        ])
    }

    public func toTokenUsage() -> TokenUsage {
        TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadInputTokens,
            cacheCreationTokens: cacheCreationInputTokens,
            cacheCreation1hTokens: cacheCreation1hTokens,
            confidence: .localParsed
        )
    }
}
