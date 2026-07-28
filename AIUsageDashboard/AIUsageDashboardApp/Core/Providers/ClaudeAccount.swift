import CryptoKit
import Foundation

/// One Claude Code account — one **Anthropic identity**, not one config directory.
///
/// Claude Code supports several accounts on one machine by pointing `CLAUDE_CONFIG_DIR` at
/// different directories (`~/.claude`, `~/.claude-account-1`, …). Each gets its own session
/// logs under `<dir>/projects` **and its own Keychain item**: the default directory uses the
/// bare service name, every other directory uses `"Claude Code-credentials-<hash>"` where
/// `<hash>` is the first 8 hex characters of the SHA-256 of the directory's absolute path.
///
/// Tokei used to hardcode the bare service name and `~/.claude`, so it reported one account's
/// quota and token count as if they were the whole picture. Then it keyed accounts on the
/// *directory*, which is wrong in both directions: one identity signed in from two directories
/// was listed and graphed twice (and its shared quota drawn as two independent gauges), while
/// two identities that took turns in a single `~/.claude` collapsed into one. The identity is
/// `oauthAccount.accountUuid` in the directory's config JSON — see `accountUUID`.
///
/// SECURITY INVARIANT: this type holds paths, a Keychain *service name*, and an account UUID
/// only — never a token, an email address, or the Keychain item's contents.
public struct ClaudeAccount: Sendable, Equatable, Identifiable, Hashable {
    /// The canonical `CLAUDE_CONFIG_DIR` for this identity — the value a caller exports to
    /// address it. When one identity owns several directories, `discover()` picks this one;
    /// see `canonicalDirectory(among:)` for the rule.
    public let configDirectory: URL
    /// The identity's *other* config directories, if it is signed in from more than one.
    /// Their logs count toward this account, and their Keychain items hold credentials for
    /// the same Anthropic account — so they are the fallback when the canonical directory's
    /// item cannot be read. See `credentialCandidates`.
    public let additionalDirectories: [URL]
    /// `oauthAccount.accountUuid` from the config JSON — the Anthropic account this
    /// directory is signed in to. `nil` when it could not be read (never signed in, config
    /// absent or malformed), which is why an unreadable identity is **never** merged with
    /// another: unknown is not a value two directories can share.
    public let accountUUID: String?
    /// Whether the canonical directory is the default (`~/.claude`) one, which is the one
    /// addressed when `CLAUDE_CONFIG_DIR` is unset — and the only one stored under the
    /// unsuffixed service.
    public let isDefault: Bool

    public var id: String { configDirectory.path }

    public init(
        configDirectory: URL,
        additionalDirectories: [URL] = [],
        accountUUID: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.configDirectory = configDirectory.standardizedFileURL
        self.additionalDirectories = additionalDirectories.map(\.standardizedFileURL)
        self.accountUUID = accountUUID
        self.isDefault = self.configDirectory.path
            == home.appendingPathComponent(Self.defaultDirectoryName, isDirectory: true)
            .standardizedFileURL.path
    }

    /// Every config directory this identity owns, canonical first.
    public var configDirectories: [URL] { [configDirectory] + additionalDirectories }

    /// Each of this identity's directories as a standalone account, canonical first — the
    /// order to try when reading credentials.
    ///
    /// Every directory authenticates to the same Anthropic account, but each one has its
    /// **own** Keychain item, and the canonical's may hold nothing: `discover()` lists
    /// `~/.claude` whether or not that directory exists (its identity comes from
    /// `~/.claude.json`, which sits outside it), so a merged identity can be canonicalized on
    /// a directory that was deleted while the sibling holding the credentials is still signed
    /// in. Asking a sibling is the same question about the same quota, not a second one.
    ///
    /// `home` is recovered from each directory's parent, which is what it is by construction:
    /// every discovered directory is `<home>/.claude*`. So a member that really is `~/.claude`
    /// still resolves to the unsuffixed service name.
    public var credentialCandidates: [ClaudeAccount] {
        [self] + additionalDirectories.map {
            ClaudeAccount(
                configDirectory: $0,
                accountUUID: accountUUID,
                home: $0.deletingLastPathComponent()
            )
        }
    }

    /// Short human label: `"default"`, or the suffix of a `.claude-*` directory
    /// (`.claude-account-2` → `"account-2"`). Falls back to the directory name. It names the
    /// **canonical** directory, so an identity signed in from two of them is labelled by the
    /// one you would export — `additionalDirectories` is where the rest are.
    public var label: String {
        isDefault ? "default" : Self.label(of: configDirectory)
    }

    /// The Keychain generic-password service holding this account's OAuth credentials.
    public var keychainService: String {
        isDefault
            ? Self.baseKeychainService
            : "\(Self.baseKeychainService)-\(Self.pathHash(configDirectory))"
    }

    /// Where this account's session logs live — one entry per config directory it owns,
    /// canonical first. Plural because an identity signed in from two directories did its
    /// work in both, and both sets of logs are its own.
    public var projectsDirectories: [URL] {
        configDirectories.map { $0.appendingPathComponent("projects", isDirectory: true) }
    }

    /// Suffix that keeps per-account cache/cooldown files apart. Empty for the default
    /// account so its existing `claude-usage-cache.json` keeps being used rather than
    /// orphaned — this is a live upgrade, not a fresh install.
    public var storageKey: String {
        isDefault ? "" : "-\(Self.pathHash(configDirectory))"
    }

    // MARK: - Discovery

    /// Every account on this machine, **deduplicated by identity**: the default directory,
    /// plus any sibling `~/.claude-*` directory that actually holds session logs, grouped so
    /// that directories signed in to the same Anthropic account come back as one entry.
    ///
    /// The `projects/` requirement is what distinguishes an account from the other
    /// `.claude-*` entries in a home directory — `~/.claude-worktrees` is a worktree
    /// scratch area, not a fourth account, and must not be counted as one.
    ///
    /// Grouping is by `oauthAccount.accountUuid`, read from disk. Directories whose identity
    /// cannot be read stay separate — see `accountUUID`. Order is the directory order the
    /// old discovery returned (default first, then siblings by label), taken from each
    /// group's first directory, so a machine with no duplicates sees exactly what it saw
    /// before.
    public static func discover(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [ClaudeAccount] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        let siblings = contents
            .filter { url in
                let name = url.lastPathComponent
                guard name.hasPrefix(defaultDirectoryName + "-") else { return false }
                var isDirectory: ObjCBool = false
                let projects = url.appendingPathComponent("projects", isDirectory: true)
                guard fileManager.fileExists(atPath: projects.path, isDirectory: &isDirectory) else {
                    return false
                }
                return isDirectory.boolValue
            }
            .sorted { label(of: $0) < label(of: $1) }

        // The default directory is listed whether or not it exists — a fresh install still
        // has credentials worth reading — so it always heads the list.
        let directories = [home.appendingPathComponent(defaultDirectoryName, isDirectory: true)]
            + siblings

        return group(directories, home: home, fileManager: fileManager)
    }

    /// Folds config directories into one account per identity, preserving input order.
    static func group(
        _ directories: [URL],
        home: URL,
        fileManager: FileManager = .default
    ) -> [ClaudeAccount] {
        var order: [String] = []
        var members: [String: [URL]] = [:]

        for directory in directories {
            let uuid = accountUUID(of: directory, fileManager: fileManager)
            // An unreadable identity gets a key of its own. Two directories that both fail
            // to identify themselves are not thereby the same account — merging them would
            // silently fuse two people's usage, which is worse than listing one twice.
            let key = uuid.map { "uuid:\($0)" } ?? "path:\(directory.standardizedFileURL.path)"
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(directory)
        }

        return order.map { key in
            let group = members[key] ?? []
            let canonical = canonicalDirectory(among: group, home: home)
            return ClaudeAccount(
                configDirectory: canonical,
                additionalDirectories: group.filter {
                    $0.standardizedFileURL.path != canonical.standardizedFileURL.path
                },
                accountUUID: key.hasPrefix("uuid:") ? String(key.dropFirst("uuid:".count)) : nil,
                home: home
            )
        }
    }

    /// Which of an identity's directories a caller should export as `CLAUDE_CONFIG_DIR`.
    ///
    /// `~/.claude` when it is a member: it is the directory Claude Code uses with no
    /// environment variable set, so it addresses this account from any shell, including ones
    /// that never learned about the others. Otherwise the **first directory in discovery
    /// order** — default first, then siblings by label.
    ///
    /// This used to be "the most recently active directory", by `projects/` mtime. That made
    /// the account's whole persistent identity — `id`, `storageKey`, `keychainService` and
    /// the label the user reads — a function of the most volatile stat on the machine: one
    /// session written under a sibling `CLAUDE_CONFIG_DIR` moved all four, which destroyed
    /// and rebuilt the SwiftUI row, renamed `claude-usage-cooldown<storageKey>.json` (so the
    /// app could re-hit the Anthropic usage endpoint inside its own backoff window), and
    /// orphaned the quota cache. Discovery order is derived from directory names, which do
    /// not move, so the identity is stable for the lifetime of the group.
    static func canonicalDirectory(among directories: [URL], home: URL) -> URL {
        let defaultPath = home.appendingPathComponent(defaultDirectoryName, isDirectory: true)
            .standardizedFileURL.path
        if let defaultDirectory = directories.first(where: {
            $0.standardizedFileURL.path == defaultPath
        }) {
            return defaultDirectory
        }
        return directories.first ?? home.appendingPathComponent(defaultDirectoryName, isDirectory: true)
    }

    // MARK: - Identity

    /// The Anthropic account a config directory is signed in to, or `nil` if that cannot be
    /// established. Reads only `oauthAccount.accountUuid`; the rest of the file — including
    /// the email address and the organization — is not this type's business.
    static func accountUUID(of directory: URL, fileManager: FileManager = .default) -> String? {
        for url in configFileCandidates(for: directory) {
            guard let data = fileManager.contents(atPath: url.path),
                  let config = try? JSONDecoder().decode(ConfigIdentity.self, from: data),
                  let uuid = config.oauthAccount?.accountUuid,
                  !uuid.isEmpty else { continue }
            return uuid
        }
        return nil
    }

    /// Where Claude Code keeps the config JSON holding `oauthAccount`, in the order to try.
    ///
    /// With `CLAUDE_CONFIG_DIR` set it lives *inside* the directory, as `<dir>/.claude.json`.
    /// With it unset — the default account — it lives beside it, as `~/.claude.json`. Both
    /// shapes are checked rather than branching on `isDefault`, because a directory can be
    /// addressed either way and only one of the two files will exist.
    static func configFileCandidates(for directory: URL) -> [URL] {
        let standardized = directory.standardizedFileURL
        return [
            standardized.appendingPathComponent(".claude.json", isDirectory: false),
            standardized.deletingLastPathComponent()
                .appendingPathComponent(standardized.lastPathComponent + ".json", isDirectory: false)
        ]
    }

    /// The `~/.claude.json` subset this type reads. Decoding the whole file would pull in
    /// project history and MCP config Tokei has no business holding.
    private struct ConfigIdentity: Decodable {
        struct OAuthAccount: Decodable {
            let accountUuid: String?
        }

        let oauthAccount: OAuthAccount?
    }

    // MARK: - Internals

    static let defaultDirectoryName = ".claude"
    static let baseKeychainService = "Claude Code-credentials"

    /// `label` before an account exists — discovery sorts directories by it.
    private static func label(of directory: URL) -> String {
        let name = directory.lastPathComponent
        let prefix = defaultDirectoryName + "-"
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    /// First 8 hex characters of SHA-256 over the directory's absolute path — the scheme
    /// Claude Code itself uses, confirmed against the real login keychain on 2026-07-27.
    static func pathHash(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
