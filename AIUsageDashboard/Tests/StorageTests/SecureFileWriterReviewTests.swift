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

    func testHardeningDoesNotChmodTargetAfterChildIsSwappedForSymlink() throws {
        try assertSwappedChildKeepsTargetMode(isDirectory: false)
    }

    func testHardeningDoesNotChmodTargetAfterDirectoryIsSwappedForSymlink() throws {
        try assertSwappedChildKeepsTargetMode(isDirectory: true)
    }

    private func assertSwappedChildKeepsTargetMode(isDirectory: Bool) throws {
        let root = directory.appendingPathComponent("support")
        let child = root.appendingPathComponent("swapped")
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if isDirectory {
            for url in [child, outside] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        } else {
            for url in [child, outside] { try Data("fixture".utf8).write(to: url) }
        }
        let mode = isDirectory ? 0o755 : 0o644
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: outside.path)
        let manager = SwappingChildManager(target: outside)
        try SecureFileWriter.hardenExistingDirectory(at: root, using: manager)
        XCTAssertTrue(manager.didSwap)
        let actual = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(actual?.intValue, mode)
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
        let children = try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for child in children where child.lastPathComponent == "a-fail.json" {
            _ = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            try removeItem(at: child)
            lock.withLock { failed += 1 }
        }
        return children
    }
}

private final class SwappingChildManager: FileManager, @unchecked Sendable {
    let target: URL
    private(set) var didSwap = false

    init(target: URL) { self.target = target; super.init() }

    override func contentsOfDirectory(
        at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        let children = try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
        for child in children where child.lastPathComponent == "swapped" && !didSwap {
            // Keep the observed regular-file/directory values, then simulate the
            // directory entry changing before the later permission syscall.
            _ = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            try removeItem(at: child)
            try createSymbolicLink(at: child, withDestinationURL: target)
            didSwap = true
        }
        return children
    }
}
