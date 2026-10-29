import Darwin
import XCTest
@testable import AIUsageDashboardCore

final class ReviewCLIFormatTests: XCTestCase {
    func testHelpClosedStdoutKeepsDefaultSIGPIPEInsteadOfAborting() throws {
        let output = try ReviewCLIProbe.run(["help"], closedOutput: true)
        XCTAssertEqual(output.reason, .uncaughtSignal)
        XCTAssertEqual(output.status, SIGPIPE)
    }

    func testStatusJSONRemainsPrettyPrinted() throws {
        let snapshot = try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: Data(AgentSnapshotFixtures.full.utf8))
        let output = try ReviewCLIProbe.run(["status", "--json"], snapshot: snapshot)
        XCTAssertEqual(output.status, 0)
        XCTAssertGreaterThan(output.text.split(separator: "\n").count, 2)
        XCTAssertNoThrow(try AgentSnapshot.makeDecoder().decode(AgentSnapshot.self, from: Data(output.text.utf8)))
    }
}
