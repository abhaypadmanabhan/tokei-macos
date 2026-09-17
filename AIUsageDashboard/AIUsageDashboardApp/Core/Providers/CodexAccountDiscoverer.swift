import Foundation

private struct CodexAuthMetadata: Decodable {
    let tokens: CodexAuthTokenMetadata?
}

private struct CodexAuthTokenMetadata: Decodable {
    let accountID: String?

    private enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
    }
}

/// Discovers isolated Codex homes without reading token fields from `auth.json`.
public final class CodexAccountDiscoverer: AccountDiscovering, @unchecked Sendable {
    public let providerID: ProviderID = .codex

    private let identityCache = FileMetadataCache<String>()

    public init() {}

    public func discover(context: DiscoveryContext) throws -> [ProviderAccount] {
        let defaultRoot = context.home.appendingPathComponent(".codex", isDirectory: true)
        let roots = [defaultRoot]
            + [context.inheritedRoot].compactMap { $0 }
            + context.registeredRoots
        let existing = roots.filter { context.fileManager.fileExists(atPath: $0.path) }
        let candidates = existing.map { root in
            ProviderAccountNormalizer.Candidate(
                root: root,
                label: label(for: root, defaultRoot: defaultRoot),
                quotaIdentity: identity(at: root, fileManager: context.fileManager),
                selector: AccountSelector.verified(
                    environmentKey: "CODEX_HOME",
                    root: root,
                    fileManager: context.fileManager
                )
            )
        }
        return ProviderAccountNormalizer.normalize(providerID: providerID, candidates: candidates)
    }

    private func identity(at root: URL, fileManager: FileManager) -> String? {
        let authURL = root.appendingPathComponent("auth.json", isDirectory: false)
        return identityCache.value(at: authURL, fileManager: fileManager) {
            guard let data = fileManager.contents(atPath: authURL.path),
                  let metadata = try? JSONDecoder().decode(CodexAuthMetadata.self, from: data)
            else { return nil }
            return metadata.tokens?.accountID.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private func label(for root: URL, defaultRoot: URL) -> String {
        if root.standardizedFileURL.path == defaultRoot.standardizedFileURL.path {
            return "default"
        }
        let name = root.lastPathComponent
        return name.hasPrefix(".codex-") ? String(name.dropFirst(".codex-".count)) : name
    }

}
