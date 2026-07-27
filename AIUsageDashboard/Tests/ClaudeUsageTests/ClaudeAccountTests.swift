import XCTest
@testable import AIUsageDashboardCore

/// Multi-account Claude support. This Mac runs three separate Claude Code accounts
/// (`~/.claude`, `~/.claude-account-1`, `~/.claude-account-2`) selected via
/// `CLAUDE_CONFIG_DIR`; Tokei previously read only the first and reported its numbers
/// as the whole picture.
final class ClaudeAccountTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Keychain service derivation

    /// Claude Code stores the default config dir's credentials under the bare service
    /// name, and every other config dir under `<service>-<sha256(path) prefix>`.
    func testDefaultConfigDirectoryUsesUnsuffixedKeychainService() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let account = ClaudeAccount(configDirectory: home.appendingPathComponent(".claude"), home: home)
        XCTAssertEqual(account.keychainService, "Claude Code-credentials")
    }

    /// Verified against the real login keychain on 2026-07-27: `~/.claude-account-1`
    /// hashes to `a337dfc1` and `~/.claude-account-2` to `aa058b15`, both of which are
    /// present as `Claude Code-credentials-<hash>` items.
    func testNonDefaultConfigDirectoryUsesSHA256PrefixedKeychainService() {
        let home = URL(fileURLWithPath: "/Users/abhayp", isDirectory: true)
        let one = ClaudeAccount(configDirectory: home.appendingPathComponent(".claude-account-1"), home: home)
        let two = ClaudeAccount(configDirectory: home.appendingPathComponent(".claude-account-2"), home: home)

        XCTAssertEqual(one.keychainService, "Claude Code-credentials-a337dfc1")
        XCTAssertEqual(two.keychainService, "Claude Code-credentials-aa058b15")
    }

    /// Cache and cooldown files must not collide, or accounts overwrite each other's
    /// readings and the last one to sync wins.
    func testAccountsGetDistinctStorageKeys() {
        let home = URL(fileURLWithPath: "/Users/abhayp", isDirectory: true)
        let base = ClaudeAccount(configDirectory: home.appendingPathComponent(".claude"), home: home)
        let one = ClaudeAccount(configDirectory: home.appendingPathComponent(".claude-account-1"), home: home)

        XCTAssertNotEqual(base.storageKey, one.storageKey)
        // The default account keeps the historical filename so existing caches survive.
        XCTAssertEqual(base.storageKey, "")
    }

    func testDisplayLabelUsesTheConfigDirectoryName() {
        let home = URL(fileURLWithPath: "/Users/abhayp", isDirectory: true)
        XCTAssertEqual(
            ClaudeAccount(configDirectory: home.appendingPathComponent(".claude"), home: home).label,
            "default"
        )
        XCTAssertEqual(
            ClaudeAccount(configDirectory: home.appendingPathComponent(".claude-account-2"), home: home).label,
            "account-2"
        )
    }

    // MARK: - Discovery

    func testDiscoveryFindsSiblingConfigDirectoriesThatHoldProjects() throws {
        let home = tempDirectory!
        for name in [".claude", ".claude-account-1", ".claude-account-2"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(name).appendingPathComponent("projects"),
                withIntermediateDirectories: true
            )
        }
        // No `projects/` → not an account (this is exactly `~/.claude-worktrees` on the
        // real machine, which must not be mistaken for a fourth account).
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude-worktrees"),
            withIntermediateDirectories: true
        )

        let accounts = ClaudeAccount.discover(home: home)

        XCTAssertEqual(accounts.map(\.label), ["default", "account-1", "account-2"])
    }

    /// The default account is listed even with no `projects/` yet — a fresh install
    /// still has credentials worth reading.
    func testDiscoveryAlwaysIncludesTheDefaultAccount() {
        let accounts = ClaudeAccount.discover(home: tempDirectory)
        XCTAssertEqual(accounts.map(\.label), ["default"])
    }
}
