import Foundation
import CoreFoundation

enum TokenArithmetic {
    static func adding(_ lhs: Int, _ rhs: Int) -> Int {
        var overflowed = false
        return adding(lhs, rhs, overflowed: &overflowed)
    }

    static func adding(_ lhs: Int, _ rhs: Int, overflowed: inout Bool) -> Int {
        let (value, didOverflow) = lhs.addingReportingOverflow(rhs)
        guard didOverflow else { return value }
        overflowed = true
        return rhs >= 0 ? .max : .min
    }

    static func subtracting(_ lhs: Int, _ rhs: Int) -> Int {
        var overflowed = false
        return subtracting(lhs, rhs, overflowed: &overflowed)
    }

    static func subtracting(_ lhs: Int, _ rhs: Int, overflowed: inout Bool) -> Int {
        let (value, didOverflow) = lhs.subtractingReportingOverflow(rhs)
        guard didOverflow else { return value }
        overflowed = true
        return rhs >= 0 ? .min : .max
    }

    static func multiplied(_ lhs: Int, by rhs: Int, overflowed: inout Bool) -> Int {
        let (value, didOverflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard didOverflow else { return value }
        overflowed = true
        return (lhs >= 0) == (rhs >= 0) ? .max : .min
    }

    static func sum<S: Sequence>(_ values: S) -> Int where S.Element == Int {
        var overflowed = false
        return sum(values, overflowed: &overflowed)
    }

    static func sum<S: Sequence>(_ values: S, overflowed: inout Bool) -> Int where S.Element == Int {
        values.reduce(0) { adding($0, $1, overflowed: &overflowed) }
    }
}

enum CheckedNumericConversion {
    static func integer(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }
        if let integer = value as? Int { return integer }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              number.compare(NSNumber(value: Int.min)) != .orderedAscending,
              number.compare(NSNumber(value: Int.max)) != .orderedDescending else {
            return nil
        }
        return number.intValue
    }

    static func tokenCount(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return 0 }
        guard let integer = integer(value), integer >= 0 else { return nil }
        return integer
    }

    static func optionalTokenCount(_ value: Any?) -> (isValid: Bool, value: Int?) {
        guard let value, !(value is NSNull) else { return (true, nil) }
        guard let integer = integer(value), integer >= 0 else { return (false, nil) }
        return (true, integer)
    }
}

public struct TokenUsage: Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheCreationTokens: Int?
    public let reasoningTokens: Int?
    public var totalTokens: Int? {
        let all: [Int?] = [inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, reasoningTokens]
        if all.allSatisfy({ $0 == nil }) { return nil }
        return TokenArithmetic.sum(all.compactMap { $0 })
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
        var overflowed = false
        return merging(other, overflowed: &overflowed)
    }

    func merging(_ other: TokenUsage, overflowed: inout Bool) -> TokenUsage {
        TokenUsage(
            inputTokens: TokenArithmetic.adding(
                inputTokens ?? 0,
                other.inputTokens ?? 0,
                overflowed: &overflowed
            ),
            outputTokens: TokenArithmetic.adding(
                outputTokens ?? 0,
                other.outputTokens ?? 0,
                overflowed: &overflowed
            ),
            cacheReadTokens: TokenArithmetic.adding(
                cacheReadTokens ?? 0,
                other.cacheReadTokens ?? 0,
                overflowed: &overflowed
            ),
            cacheCreationTokens: TokenArithmetic.adding(
                cacheCreationTokens ?? 0,
                other.cacheCreationTokens ?? 0,
                overflowed: &overflowed
            ),
            reasoningTokens: TokenArithmetic.adding(
                reasoningTokens ?? 0,
                other.reasoningTokens ?? 0,
                overflowed: &overflowed
            ),
            confidence: minConfidence(confidence, other.confidence)
        )
    }

    private func minConfidence(_ a: MetricConfidence, _ b: MetricConfidence) -> MetricConfidence {
        let order: [MetricConfidence] = [.exact, .providerReported, .localParsed, .estimated, .unavailable]
        guard let ia = order.firstIndex(of: a), let ib = order.firstIndex(of: b) else { return .unavailable }
        return order[max(ia, ib)]
    }
}

enum UsageAggregation {
    /// Preserve an unavailable field as `nil` and take confidence from a usage that
    /// actually contributed numbers, rather than whichever provider happened to run first.
    static func sum(_ usages: [TokenUsage]) -> TokenUsage {
        func total(_ keyPath: KeyPath<TokenUsage, Int?>) -> Int? {
            let values = usages.compactMap { $0[keyPath: keyPath] }
            return values.isEmpty ? nil : TokenArithmetic.sum(values)
        }
        return TokenUsage(
            inputTokens: total(\.inputTokens),
            outputTokens: total(\.outputTokens),
            cacheReadTokens: total(\.cacheReadTokens),
            cacheCreationTokens: total(\.cacheCreationTokens),
            reasoningTokens: total(\.reasoningTokens),
            confidence: usages.first { $0.totalTokens != nil }?.confidence ?? .unavailable
        )
    }

    static func merge(_ totals: [[Date: Int]]) -> [Date: Int]? {
        guard !totals.isEmpty else { return nil }
        return totals.reduce(into: [:]) { merged, next in
            merged.merge(next, uniquingKeysWith: TokenArithmetic.adding)
        }
    }
}
