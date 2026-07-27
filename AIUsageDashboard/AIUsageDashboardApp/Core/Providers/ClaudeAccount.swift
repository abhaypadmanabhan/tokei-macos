import CryptoKit
import Foundation

/// One Claude Code account, identified by the config directory `CLAUDE_CONFIG_DIR` points at.
///
/// Claude Code supports several accounts on one machine by pointing `CLAUDE_CONFIG_DIR` at
/// different directories (`~/.claude`, `~/.claude-account-1`, …). Each gets its own session
/// logs under `<dir>/projects` **and its own Keychain item**: the default directory uses the
/// bare service name, every other directory uses `"Claude Code-credentials-<hash>"` where
/// `<hash>` is the first 8 hex characters of the SHA-256 of the directory's absolute path.
///
/// Tokei used to hardcode the bare service name and `~/.claude`, so it reported one account's
/// quota and token count as if they were the whole picture.
///
/// SECURITY INVARIANT: this type holds paths and a Keychain *service name* only — never a
/// token or the item's contents.
public struct ClaudeAccount: Sendable, Equatable, Identifiable, Hashable {
    /// The `CLAUDE_CONFIG_DIR` this account corresponds to.
    public let configDirectory: URL
    /// Whether this is the default (`~/.claude`) account, which is the one addressed when
    /// `CLAUDE_CONFIG_DIR` is unset — and the only one stored under the unsuffixed service.
    public let isDefault: Bool

    public var id: String { configDirectory.path }

    public init(configDirectory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.configDirectory = configDirectory.standardizedFileURL
        self.isDefault = self.configDirectory.path
            == home.appendingPathComponent(Self.defaultDirectoryName, isDirectory: true)
            .standardizedFileURL.path
    }

    /// Short human label: `"default"`, or the suffix of a `.claude-*` directory
    /// (`.claude-account-2` → `"account-2"`). Falls back to the directory name.
    public var label: String {
        if isDefault { return "default" }
        let name = configDirectory.lastPathComponent
        let prefix = Self.defaultDirectoryName + "-"
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    /// The Keychain generic-password service holding this account's OAuth credentials.
    public var keychainService: String {
        isDefault
            ? Self.baseKeychainService
            : "\(Self.baseKeychainService)-\(Self.pathHash(configDirectory))"
    }

    /// Where this account's session logs live.
    public var projectsDirectory: URL {
        configDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    /// Suffix that keeps per-account cache/cooldown files apart. Empty for the default
    /// account so its existing `claude-usage-cache.json` keeps being used rather than
    /// orphaned — this is a live upgrade, not a fresh install.
    public var storageKey: String {
        isDefault ? "" : "-\(Self.pathHash(configDirectory))"
    }

    // MARK: - Discovery

    /// Every account on this machine: the default one, plus any sibling `~/.claude-*`
    /// directory that actually holds session logs.
    ///
    /// The `projects/` requirement is what distinguishes an account from the other
    /// `.claude-*` entries in a home directory — `~/.claude-worktrees` is a worktree
    /// scratch area, not a fourth account, and must not be counted as one.
    public static func discover(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [ClaudeAccount] {
        let defaultAccount = ClaudeAccount(
            configDirectory: home.appendingPathComponent(defaultDirectoryName, isDirectory: true),
            home: home
        )

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
            .map { ClaudeAccount(configDirectory: $0, home: home) }
            .sorted { $0.label < $1.label }

        return [defaultAccount] + siblings
    }

    // MARK: - Internals

    static let defaultDirectoryName = ".claude"
    static let baseKeychainService = "Claude Code-credentials"

    /// First 8 hex characters of SHA-256 over the directory's absolute path — the scheme
    /// Claude Code itself uses, confirmed against the real login keychain on 2026-07-27.
    static func pathHash(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
