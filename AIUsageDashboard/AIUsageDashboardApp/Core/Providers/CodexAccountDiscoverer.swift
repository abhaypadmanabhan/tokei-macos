import Foundation

private struct CodexAuthMetadata: Decodable {
    let account: CodexAuthAccount?
    let accountID: String?
    let accountId: String?

    private enum CodingKeys: String, CodingKey {
        case account
        case accountID = "account_id"
        case accountId
    }
}

private struct CodexAuthAccount: Decodable {
    let id: String?
}

/// Discovers isolated Codex homes without reading token fields from `auth.json`.
public final class CodexAccountDiscoverer: AccountDiscovering, @unchecked Sendable {
    public let providerID: ProviderID = .codex

    private struct MetadataStamp: Equatable {
        let size: UInt64
        let modifiedAt: Date?
        let fileNumber: UInt64?
    }

    private struct CachedIdentity {
        let stamp: MetadataStamp
        let identity: String?
    }

    private let lock = NSLock()
    private var identityCache: [String: CachedIdentity] = [:]

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
        guard let attributes = try? fileManager.attributesOfItem(atPath: authURL.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            lock.lock()
            identityCache.removeValue(forKey: authURL.path)
            lock.unlock()
            return nil
        }
        let stamp = MetadataStamp(
            size: size,
            modifiedAt: attributes[.modificationDate] as? Date,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
        lock.lock()
        if let cached = identityCache[authURL.path], cached.stamp == stamp {
            lock.unlock()
            return cached.identity
        }
        lock.unlock()

        let identity: String?
        if let data = fileManager.contents(atPath: authURL.path),
           let metadata = try? JSONDecoder().decode(CodexAuthMetadata.self, from: data) {
            identity = metadata.account?.id ?? metadata.accountID ?? metadata.accountId
        } else {
            identity = nil
        }

        lock.lock()
        identityCache[authURL.path] = CachedIdentity(stamp: stamp, identity: identity)
        lock.unlock()
        return identity?.isEmpty == false ? identity : nil
    }

    private func label(for root: URL, defaultRoot: URL) -> String {
        if root.standardizedFileURL.path == defaultRoot.standardizedFileURL.path {
            return "default"
        }
        let name = root.lastPathComponent
        return name.hasPrefix(".codex-") ? String(name.dropFirst(".codex-".count)) : name
    }

}
