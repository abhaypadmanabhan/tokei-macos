import Foundation

public struct TokenUsage: Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheCreationTokens: Int?
    public let reasoningTokens: Int?
    public var totalTokens: Int? {
        let all: [Int?] = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, reasoningTokens]
        if all.allSatisfy({ $0 == nil }) { return nil }
        return all.compactMap { $0 }.reduce(0, +)
    }
    public let confidence: MetricConfidence

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        confidence: MetricConfidence
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.confidence = confidence
    }

    public static let unavailable = TokenUsage(confidence: .unavailable)

    public func merging(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: (inputTokens ?? 0) + (other.inputTokens ?? 0),
            outputTokens: (outputTokens ?? 0) + (other.outputTokens ?? 0),
            cacheReadTokens: (cacheReadTokens ?? 0) + (other.cacheReadTokens ?? 0),
            cacheCreationTokens: (cacheCreationTokens ?? 0) + (other.cacheCreationTokens ?? 0),
            reasoningTokens: (reasoningTokens ?? 0) + (other.reasoningTokens ?? 0),
            confidence: minConfidence(confidence, other.confidence)
        )
    }

    private func minConfidence(_ a: MetricConfidence, _ b: MetricConfidence) -> MetricConfidence {
        let order: [MetricConfidence] = [.exact, .providerReported, .localParsed, .estimated, .unavailable]
        guard let ia = order.firstIndex(of: a), let ib = order.firstIndex(of: b) else { return .unavailable }
        return order[max(ia, ib)]
    }
}

