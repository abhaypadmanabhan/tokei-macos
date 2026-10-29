import XCTest
@testable import AIUsageDashboardCore

final class SecureFileWriterReviewTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testHardeningContinuesAfterOneChildFails() throws {
        let failed = directory.appendingPathComponent("a-fail.json")
        let healthy = directory.appendingPathComponent("b-healthy.json")
        try Data().write(to: failed)
        try Data().write(to: healthy)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: healthy.path)
        let manager = FailingChildManager()
        XCTAssertNoThrow(try SecureFileWriter.hardenExistingDirectory(at: directory, using: manager))
        let mode = try FileManager.default.attributesOfItem(atPath: healthy.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertEqual(manager.failedChildren, 1)
    }

    func testHardeningResolvesRootButDoesNotFollowChildFileLink() throws {
        let root = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("usage-store.json")
        let outside = directory.appendingPathComponent("outside.json")
        try Data().write(to: file)
        try Data("outside".utf8).write(to: outside)
        for path in [file, outside] {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
        }
        let childLink = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: childLink, withDestinationURL: outside)
        let rootLink = directory.appendingPathComponent("support")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: root)
        XCTAssertNoThrow(try SecureFileWriter.hardenExistingDirectory(at: rootLink))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let outsideMode = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(outsideMode?.intValue, 0o644)
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
        XCTAssertTrue(try childLink.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }
}

private final class FailingChildManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var failed = 0
    var failedChildren: Int { lock.withLock { failed } }

    override func contentsOfDirectory(
        at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if URL(fileURLWithPath: path).lastPathComponent == "a-fail.json" {
            lock.withLock { failed += 1 }
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}
