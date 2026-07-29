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

    // MARK: - Identity

    /// The asymmetry that makes this whole thing a bug rather than a rounding error: the
    /// default account's config JSON is a **sibling** of its config directory
    /// (`~/.claude.json`, because `CLAUDE_CONFIG_DIR` is unset for it), while every other
    /// account keeps it *inside* (`~/.claude-account-2/.claude.json`). Verified on the real
    /// machine 2026-07-28: there is no `~/.claude/.claude.json`. A lookup that only checks
    /// inside leaves the default account with an unknown identity — and the default account
    /// is exactly the one that has to merge here.
    func testDefaultAccountIdentityIsReadFromTheSiblingConfigFile() throws {
        let home = tempDirectory!
        try makeConfigDirectory(".claude", identity: "uuid-a", configInside: false)

        XCTAssertEqual(
            ClaudeAccount.accountUUID(of: home.appendingPathComponent(".claude")),
            "uuid-a"
        )
    }

    func testNonDefaultAccountIdentityIsReadFromInsideTheConfigDirectory() throws {
        let home = tempDirectory!
        try makeConfigDirectory(".claude-account-1", identity: "uuid-b", configInside: true)

        XCTAssertEqual(
            ClaudeAccount.accountUUID(of: home.appendingPathComponent(".claude-account-1")),
            "uuid-b"
        )
    }

    // MARK: - Identity deduplication

    /// The bug this task exists for. One Anthropic account signed in from two config
    /// directories was listed twice — its tokens counted from both on the way in, and one
    /// shared quota drawn as two independent gauges on the way out.
    func testTwoDirectoriesWithTheSameAccountUUIDCollapseToOneAccount() throws {
        try makeConfigDirectory(".claude", identity: "uuid-a", configInside: false)
        try makeConfigDirectory(".claude-account-2", identity: "uuid-a", configInside: true)

        let accounts = ClaudeAccount.discover(home: tempDirectory)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.accountUUID, "uuid-a")
        XCTAssertEqual(
            accounts.first?.configDirectories.map(\.lastPathComponent),
            [".claude", ".claude-account-2"]
        )
    }

    /// `accounts[].id` is what an agent exports as `CLAUDE_CONFIG_DIR`, so the merged
    /// account has to keep pointing at a directory that really addresses it. `~/.claude`
    /// wins when it is a member: it is the directory Claude Code uses with the variable
    /// unset, so it works from any shell.
    func testMergedAccountPrefersTheDefaultDirectoryAsItsConfigDirectory() throws {
        try makeConfigDirectory(".claude", identity: "uuid-a", configInside: false)
        try makeConfigDirectory(".claude-account-2", identity: "uuid-a", configInside: true)

        let accounts = ClaudeAccount.discover(home: tempDirectory)

        XCTAssertEqual(accounts.first?.configDirectory.lastPathComponent, ".claude")
        XCTAssertEqual(accounts.first?.label, "default")
        XCTAssertTrue(accounts.first?.isDefault == true, "so it keeps the unsuffixed Keychain service")
    }

    /// When the default directory is not one of the members, the canonical is the first
    /// directory discovery returned — not the most recently active one. Activity is
    /// `projects/` mtime, which advances every time Claude writes a session; see
    /// `testASessionInAnotherDirectoryDoesNotMoveTheAccountsIdentity` for what that cost.
    func testMergedAccountWithoutTheDefaultTakesTheFirstDirectoryInDiscoveryOrder() throws {
        let home = tempDirectory!
        try makeConfigDirectory(".claude-account-1", identity: "uuid-b", configInside: true)
        try makeConfigDirectory(".claude-account-2", identity: "uuid-b", configInside: true)
        // account-2's logs are a day newer than account-1's — under the old rule that was
        // enough to make account-2 the canonical.
        try setProjectsModified(".claude-account-1", to: Date().addingTimeInterval(-86_400))
        try setProjectsModified(".claude-account-2", to: Date())

        let accounts = ClaudeAccount.discover(home: home)

        // The synthetic default (no config, no identity) plus the one merged account.
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.last?.configDirectory.lastPathComponent, ".claude-account-1")
        XCTAssertEqual(
            accounts.last?.additionalDirectories.map(\.lastPathComponent),
            [".claude-account-2"]
        )
    }

    /// The account's whole persistent identity — `id` (which is `Identifiable`, and what an
    /// agent exports as `CLAUDE_CONFIG_DIR`), `storageKey`, `keychainService` and the label
    /// the user reads — is derived from the canonical directory. Deriving the canonical from
    /// `projects/` mtime made all four a function of which directory was written to last:
    /// one session under a sibling `CLAUDE_CONFIG_DIR` destroyed and rebuilt the SwiftUI row,
    /// renamed `claude-usage-cooldown<storageKey>.json` (so the app could re-hit the
    /// Anthropic usage endpoint inside its own backoff window), abandoned the quota cache,
    /// and changed the label with no action from the user.
    func testASessionInAnotherDirectoryDoesNotMoveTheAccountsIdentity() throws {
        try makeConfigDirectory(".claude-account-1", identity: "uuid-b", configInside: true)
        try makeConfigDirectory(".claude-account-3", identity: "uuid-b", configInside: true)
        try setProjectsModified(".claude-account-1", to: Date())
        try setProjectsModified(".claude-account-3", to: Date().addingTimeInterval(-86_400))
        let before = try XCTUnwrap(
            ClaudeAccount.discover(home: tempDirectory).first { $0.accountUUID == "uuid-b" }
        )

        // The user runs one session under `CLAUDE_CONFIG_DIR=~/.claude-account-3`.
        try setProjectsModified(".claude-account-3", to: Date().addingTimeInterval(60))
        let after = try XCTUnwrap(
            ClaudeAccount.discover(home: tempDirectory).first { $0.accountUUID == "uuid-b" }
        )

        XCTAssertEqual(before.id, after.id, "id is Identifiable and a usable CLAUDE_CONFIG_DIR")
        XCTAssertEqual(before.storageKey, after.storageKey, "cache and cooldown filenames")
        XCTAssertEqual(before.keychainService, after.keychainService)
        XCTAssertEqual(before.label, after.label)
    }

    func testDifferentAccountUUIDsStayTwoAccounts() throws {
        try makeConfigDirectory(".claude", identity: "uuid-a", configInside: false)
        try makeConfigDirectory(".claude-account-1", identity: "uuid-b", configInside: true)

        let accounts = ClaudeAccount.discover(home: tempDirectory)

        XCTAssertEqual(accounts.map(\.label), ["default", "account-1"])
        XCTAssertEqual(accounts.map(\.accountUUID), ["uuid-a", "uuid-b"])
        XCTAssertTrue(accounts.allSatisfy { $0.additionalDirectories.isEmpty })
    }

    /// The fallback for a directory whose identity cannot be established: it stays on its
    /// own. "Unknown" is not a value two directories can share — merging on it would fuse
    /// two people's usage into one row, which is a worse failure than listing one twice.
    func testDirectoriesWithNoReadableIdentityAreNeverMergedWithEachOther() throws {
        try makeConfigDirectory(".claude-account-1", identity: nil, configInside: true)
        try makeConfigDirectory(".claude-account-2", identity: nil, configInside: true)

        let accounts = ClaudeAccount.discover(home: tempDirectory)

        XCTAssertEqual(accounts.map(\.label), ["default", "account-1", "account-2"])
        XCTAssertTrue(accounts.allSatisfy { $0.accountUUID == nil })
        XCTAssertTrue(accounts.allSatisfy { $0.additionalDirectories.isEmpty })
    }

    /// A malformed config is the same situation as a missing one — unknown, not shared.
    func testMalformedConfigLeavesTheIdentityUnknownRatherThanCrashing() throws {
        let home = tempDirectory!
        try makeConfigDirectory(".claude-account-1", identity: nil, configInside: true)
        try Data("{not json".utf8).write(
            to: home.appendingPathComponent(".claude-account-1/.claude.json")
        )

        XCTAssertNil(ClaudeAccount.accountUUID(of: home.appendingPathComponent(".claude-account-1")))
    }

    /// A directory that was never signed in has a config file but no `oauthAccount`.
    func testConfigWithoutAnOAuthAccountLeavesTheIdentityUnknown() throws {
        let home = tempDirectory!
        try makeConfigDirectory(".claude-account-1", identity: nil, configInside: true)
        try Data(#"{"projects":{}}"#.utf8).write(
            to: home.appendingPathComponent(".claude-account-1/.claude.json")
        )

        XCTAssertNil(ClaudeAccount.accountUUID(of: home.appendingPathComponent(".claude-account-1")))
    }

    // MARK: - Fixtures

    /// Creates `<home>/<name>/projects` and, when `identity` is given, the config JSON that
    /// names it — inside the directory (`CLAUDE_CONFIG_DIR` style) or beside it (the
    /// default account's `~/.claude.json`).
    private func makeConfigDirectory(_ name: String, identity: String?, configInside: Bool) throws {
        let home = tempDirectory!
        let directory = home.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        guard let identity else { return }
        let config = """
        {"oauthAccount":{"accountUuid":"\(identity)","emailAddress":"someone@example.com"}}
        """
        let url = configInside
            ? directory.appendingPathComponent(".claude.json")
            : home.appendingPathComponent("\(name).json")
        try Data(config.utf8).write(to: url)
    }

    /// Stands in for "Claude wrote a session here" — `projects/` mtime is what moves.
    private func setProjectsModified(_ name: String, to date: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: tempDirectory.appendingPathComponent("\(name)/projects").path
        )
    }
}
