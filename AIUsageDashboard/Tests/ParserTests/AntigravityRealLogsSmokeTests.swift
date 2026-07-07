import XCTest
@testable import AIUsageDashboardCore

final class AntigravityRealLogsSmokeTests: XCTestCase {
    func testLiveStateDatabaseParsesPlanAndCreditsWhenPresent() async throws {
        let stateDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: stateDB.path) else {
            throw XCTSkip("Antigravity state database not present on this machine")
        }

        let parsed = await AntigravityStateDBParser().parse(stateDatabaseURL: stateDB)

        XCTAssertFalse(parsed.planName?.isEmpty ?? true)
        XCTAssertGreaterThanOrEqual(parsed.availableCredits ?? -1, 0)
    }
}
