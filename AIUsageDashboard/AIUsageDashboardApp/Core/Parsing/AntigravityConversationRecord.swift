// Adapted from T3 Code: apps/server/src/provider/Drivers/antigravityUsageReader.ts (MIT).
import Foundation

struct AntigravityConversationRecord: Sendable {
    var modelID: Int
    var model: String?
    var timestamp: Date
    var timestampQuality: Int
    let keys: [String]
    var input: Int
    var cached: Int
    var creation: Int
    var output: Int
    var reasoning: Int

    var tokens: TokenUsage {
        TokenUsage(inputTokens: input, outputTokens: output - min(output, reasoning),
                   cacheReadTokens: cached, cacheCreationTokens: creation,
                   reasoningTokens: min(output, reasoning), confidence: .localParsed)
    }

    mutating func merge(_ other: Self) {
        input = max(input, other.input)
        cached = max(cached, other.cached)
        creation = max(creation, other.creation)
        output = max(output, other.output)
        reasoning = max(reasoning, other.reasoning)
        if model == nil, let name = other.model { model = name; modelID = other.modelID }
        if other.timestampQuality > timestampQuality
            || (other.timestampQuality == timestampQuality && other.timestamp < timestamp) {
            timestamp = other.timestamp
            timestampQuality = other.timestampQuality
        }
    }

    static func deduplicated(_ candidates: [Self]) -> [Self] {
        var parents = Array(candidates.indices)
        var owners: [String: Int] = [:]
        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current {
                parents[current] = parents[parents[current]]
                current = parents[current]
            }
            return current
        }
        for (index, candidate) in candidates.enumerated() {
            for key in candidate.keys {
                if let owner = owners[key] {
                    let left = root(owner)
                    let right = root(index)
                    parents[max(left, right)] = min(left, right)
                } else { owners[key] = index }
            }
        }
        var groups: [Int: Self] = [:]
        for (index, candidate) in candidates.enumerated() {
            let owner = root(index)
            if var merged = groups[owner] {
                merged.merge(candidate)
                groups[owner] = merged
            } else { groups[owner] = candidate }
        }
        return groups.keys.sorted().compactMap { groups[$0] }
    }
}

extension AntigravityConversationRecord {
    static func normalized(_ name: String?) -> String? {
        guard var name, !name.isEmpty else { return nil }
        name = name.lowercased().replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        if name.hasPrefix("claude-") {
            name = name.replacingOccurrences(of: #"^claude-(4(?:\.\d+)?)-(\w+)"#,
                                            with: "claude-$2-$1", options: .regularExpression)
                .replacingOccurrences(of: ".", with: "-")
        }
        name = name.replacingOccurrences(of: #"-(low|medium|high)$"#, with: "", options: .regularExpression)
        return name.isEmpty ? nil : name
    }

    static let knownModels: [Int: String] = [
        246: "gemini-2.5-pro", 312: "gemini-2.5-flash", 313: "gemini-2.5-flash-thinking",
        329: "gemini-2.5-flash-thinking", 330: "gemini-2.5-flash-lite",
        281: "claude-sonnet-4", 282: "claude-sonnet-4", 290: "claude-opus-4", 291: "claude-opus-4",
        333: "claude-sonnet-4-5", 334: "claude-sonnet-4-5", 340: "claude-haiku-4-5", 341: "claude-haiku-4-5",
        1026: "claude-opus-4-6", 1035: "claude-sonnet-4-6", 1016: "gemini-3.1-pro", 1036: "gemini-3.1-pro",
        1037: "gemini-3.1-pro", 1018: "gemini-3-flash-preview", 1084: "gemini-3-flash-preview",
        1047: "gemini-3-flash-preview"
    ]
}
