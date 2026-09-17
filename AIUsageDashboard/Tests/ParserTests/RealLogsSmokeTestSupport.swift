import XCTest

extension XCTestCase {
    func requireRealLogsOptIn() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TOKEI_REAL_LOGS"] == "1",
            "Set TOKEI_REAL_LOGS=1 to run live-corpus smoke tests"
        )
    }
}
