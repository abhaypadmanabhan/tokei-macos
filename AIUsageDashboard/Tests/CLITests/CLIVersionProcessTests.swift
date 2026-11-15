import XCTest
@testable import AIUsageDashboardCore

final class CLIVersionProcessTests: XCTestCase {
    func testBuiltHelperReportsProjectMarketingVersion() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("project.yml")
        let source = try String(contentsOf: project, encoding: .utf8)
        let line = try XCTUnwrap(source.split(separator: "\n").first { $0.contains("MARKETING_VERSION:") })
        let version = try XCTUnwrap(line.split(separator: "\"").dropFirst().first)
        let result = try ReviewCLIProbe.run(["version"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.text, "tokei \(version)\n")
    }
}
