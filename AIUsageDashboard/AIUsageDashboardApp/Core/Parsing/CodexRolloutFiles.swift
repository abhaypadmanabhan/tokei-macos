import Foundation

/// Rollout identity is the plain JSONL path, regardless of its storage encoding.
enum CodexRolloutFiles {
    static func isCompressed(_ url: URL) -> Bool { url.lastPathComponent.hasSuffix(".jsonl.zst") }

    static func accepts(_ url: URL) -> Bool { url.pathExtension == "jsonl" || isCompressed(url) }

    static func plainURL(_ url: URL) -> URL { isCompressed(url) ? url.deletingPathExtension() : url }

    static func sessionID(_ url: URL) -> String { plainURL(url).deletingPathExtension().lastPathComponent }

    static func preferringPlain(_ sources: [LogSource]) -> [LogSource] {
        let plainPaths = Set(sources.filter { !isCompressed($0.url) }.map(\.url.path))
        var seen: Set<String> = []
        return sources.filter { source in
            guard seen.insert(source.url.path).inserted else { return false }
            return !isCompressed(source.url) || !plainPaths.contains(plainURL(source.url).path)
        }
    }
}
