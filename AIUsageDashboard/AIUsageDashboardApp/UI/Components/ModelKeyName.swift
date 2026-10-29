import Foundation

/// A stored model key split for display. Fast-tier tokens are priced apart, so the key can
/// end in a tier (`gpt-5.5@priority`, `claude-opus-5-5@fast`); people read the base model
/// with the tier as a word, never the raw `@` key. Only these tiers split: a Vertex id such
/// as `claude-3-5-sonnet@20240620` is a model name and keeps its `@`. Pure, so the Core test
/// bundle compiles it.
struct ModelKeyName: Equatable {
    static let tiers: Set<String> = ["priority", "ultrafast", "fast"]

    let name: String
    let tier: String?

    init(_ key: String) {
        if let sign = key.lastIndex(of: "@"), sign > key.startIndex,
           Self.tiers.contains(String(key[key.index(after: sign)...])) {
            name = String(key[..<sign])
            tier = String(key[key.index(after: sign)...])
        } else {
            name = key
            tier = nil
        }
    }

    /// "gpt-5.5, priority tier": what VoiceOver and the tooltip say.
    var spoken: String {
        guard let tier else { return name }
        return "\(name), \(tier) tier"
    }
}
