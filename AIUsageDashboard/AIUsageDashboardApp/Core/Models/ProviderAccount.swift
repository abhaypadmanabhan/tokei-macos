import CryptoKit
import Foundation

/// One local profile capable of addressing a provider account.
public struct AccountProfile: Sendable, Equatable, Identifiable {
    public let id: String
    public let root: URL
    public let selector: AccountSelector?

    public init(id: String, root: URL, selector: AccountSelector?) {
        self.id = id
        self.root = root.standardizedFileURL
        self.selector = selector
    }
}

/// Provider-scoped identity plus every local profile known to represent it.
public struct ProviderAccount: Sendable, Equatable, Identifiable {
    public let id: String
    public let providerID: ProviderID
    public let legacyID: String
    public let label: String
    public let profiles: [AccountProfile]
    public let preferredProfileID: String

    public init(
        id: String,
        providerID: ProviderID,
        legacyID: String,
        label: String,
        profiles: [AccountProfile],
        preferredProfileID: String
    ) {
        self.id = id
        self.providerID = providerID
        self.legacyID = legacyID
        self.label = label
        self.profiles = profiles
        self.preferredProfileID = preferredProfileID
    }

    public var preferredProfile: AccountProfile? {
        profiles.first { $0.id == preferredProfileID }
    }
}

/// Inputs shared by provider-specific account discovery adapters.
public struct DiscoveryContext: @unchecked Sendable {
    public let home: URL
    public let registeredRoots: [URL]
    public let inheritedRoot: URL?
    public let fileManager: FileManager

    public init(
        home: URL,
        registeredRoots: [URL] = [],
        inheritedRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.home = home
        self.registeredRoots = registeredRoots
        self.inheritedRoot = inheritedRoot
        self.fileManager = fileManager
    }
}

public protocol AccountDiscovering: Sendable {
    var providerID: ProviderID { get }
    func discover(context: DiscoveryContext) throws -> [ProviderAccount]
}

/// Shared identity and grouping rules. Adapters supply roots, labels, identities and
/// selectors; this is the sole place that decides what folds into one account.
public enum ProviderAccountNormalizer {
    private struct CanonicalCandidate {
        let candidate: Candidate
        let canonicalRoot: URL
    }

    public struct Candidate: Sendable {
        public let root: URL
        public let label: String
        public let quotaIdentity: String?
        public let selector: AccountSelector?

        public init(
            root: URL,
            label: String,
            quotaIdentity: String?,
            selector: AccountSelector?
        ) {
            self.root = root
            self.label = label
            self.quotaIdentity = quotaIdentity
            self.selector = selector
        }
    }

    public static func normalize(
        providerID: ProviderID,
        candidates: [Candidate]
    ) -> [ProviderAccount] {
        var seenRoots: Set<String> = []
        let unique = candidates.compactMap { candidate -> CanonicalCandidate? in
            let canonical = candidate.root.resolvingSymlinksInPath().standardizedFileURL
            guard seenRoots.insert(canonical.path).inserted else { return nil }
            return CanonicalCandidate(
                candidate: Candidate(
                    root: candidate.root.standardizedFileURL,
                    label: candidate.label,
                    quotaIdentity: candidate.quotaIdentity,
                    selector: candidate.selector
                ),
                canonicalRoot: canonical
            )
        }

        var order: [String] = []
        var groups: [String: [CanonicalCandidate]] = [:]
        for item in unique {
            let key = item.candidate.quotaIdentity.map { "identity:\($0)" }
                ?? "root:\(item.canonicalRoot.path)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }

        return order.compactMap { key in
            guard let members = groups[key], let first = members.first else { return nil }
            let identity = first.candidate.quotaIdentity
            let accountID = identity.map { stableID(providerID: providerID, quotaIdentity: $0) }
                ?? localID(providerID: providerID, canonicalRoot: first.canonicalRoot)
            let profiles = members.map { item in
                AccountProfile(
                    id: item.candidate.root.path,
                    root: item.candidate.root,
                    selector: item.candidate.selector
                )
            }
            let preferred = profiles.first(where: { $0.selector != nil }) ?? profiles[0]
            return ProviderAccount(
                id: accountID,
                providerID: providerID,
                legacyID: first.candidate.root.path,
                label: first.candidate.label,
                profiles: profiles,
                preferredProfileID: preferred.id
            )
        }
    }

    public static func stableID(providerID: ProviderID, quotaIdentity: String) -> String {
        let input = Data((providerID.rawValue + "\0" + quotaIdentity).utf8)
        return providerID.rawValue + ":" + hexDigest(input)
    }

    public static func localID(providerID: ProviderID, canonicalRoot: URL) -> String {
        let path = canonicalRoot.resolvingSymlinksInPath().standardizedFileURL.path
        return providerID.rawValue + ":local:" + hexDigest(Data(path.utf8))
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
