import XCTest
@testable import AIUsageDashboardCore

final class ProviderAccountDiscoveryTests: XCTestCase {
    private struct SingleAccountTestDiscoverer: AccountDiscovering {
        let providerID: ProviderID
        let root: URL

        func discover(context: DiscoveryContext) throws -> [ProviderAccount] {
            ProviderAccountNormalizer.normalize(
                providerID: providerID,
                candidates: [.init(root: root, label: "default", quotaIdentity: nil, selector: nil)]
            )
        }
    }

    private var home: URL!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    func testA6_identityHashIsProviderScopedAndUsesTheFullDigest() {
        XCTAssertEqual(
            ProviderAccountNormalizer.stableID(providerID: .claudeCode, quotaIdentity: "uuid-a"),
            "claude_code:1a6f435c01e35bdbfad57cf400909a0afdbfdb4890147902b195539d35c7df7b"
        )
        XCTAssertEqual(
            ProviderAccountNormalizer.stableID(providerID: .codex, quotaIdentity: "acct-1"),
            "codex:ce063c3cded693f5ff8d76bd54de44135cb4baa14ba1097e85e421e157216b1a"
        )
    }

    func testA6_sameIdentityFoldsButUnknownIdentitiesNeverMerge() throws {
        let one = home.appendingPathComponent("one", isDirectory: true)
        let two = home.appendingPathComponent("two", isDirectory: true)
        try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)

        let folded = ProviderAccountNormalizer.normalize(providerID: .codex, candidates: [
            .init(root: one, label: "one", quotaIdentity: "acct", selector: nil),
            .init(root: two, label: "two", quotaIdentity: "acct", selector: nil)
        ])
        let unknown = ProviderAccountNormalizer.normalize(providerID: .codex, candidates: [
            .init(root: one, label: "one", quotaIdentity: nil, selector: nil),
            .init(root: two, label: "two", quotaIdentity: nil, selector: nil)
        ])

        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded[0].profiles.count, 2)
        XCTAssertEqual(unknown.count, 2)
        XCTAssertNotEqual(unknown[0].id, unknown[1].id)
    }

    func testA6_symlinkRootsDedupeWithoutReplacingTheLaunchLocator() throws {
        let target = home.appendingPathComponent("target", isDirectory: true)
        let link = home.appendingPathComponent("profile-link", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let selector = try XCTUnwrap(AccountSelector.verified(
            environmentKey: "CODEX_HOME",
            root: link
        ))

        let accounts = ProviderAccountNormalizer.normalize(providerID: .codex, candidates: [
            .init(root: link, label: "link", quotaIdentity: nil, selector: selector),
            .init(root: target, label: "target", quotaIdentity: nil, selector: nil)
        ])

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].profiles.count, 1)
        XCTAssertEqual(accounts[0].legacyID, link.standardizedFileURL.path)
        XCTAssertEqual(
            accounts[0].preferredProfile?.selector?.env["CODEX_HOME"],
            link.standardizedFileURL.path
        )
    }

    func testA6_otherProvidersUseTheSameProtocolWithoutInventingASelector() throws {
        let discoverer: any AccountDiscovering = SingleAccountTestDiscoverer(
            providerID: .cursor,
            root: home
        )
        let accounts = try discoverer.discover(context: DiscoveryContext(home: home))

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].providerID, .cursor)
        XCTAssertNil(accounts[0].preferredProfile?.selector)
    }

    func testA5_verifiedSelectorRejectsUnknownKeysMissingRootsAndFiles() throws {
        let file = home.appendingPathComponent("not-a-root")
        try Data().write(to: file)

        XCTAssertNil(AccountSelector.verified(
            environmentKey: "UNSAFE_HOME",
            root: home
        ))
        XCTAssertNil(AccountSelector.verified(
            environmentKey: "CODEX_HOME",
            root: home.appendingPathComponent("missing")
        ))
        XCTAssertNil(AccountSelector.verified(
            environmentKey: "CODEX_HOME",
            root: file
        ))
        XCTAssertEqual(
            AccountSelector.verified(environmentKey: "CODEX_HOME", root: home)?.env,
            ["CODEX_HOME": home.standardizedFileURL.path]
        )
    }
}
