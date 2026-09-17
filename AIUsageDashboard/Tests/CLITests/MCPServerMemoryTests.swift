import XCTest

final class MCPServerMemoryTests: XCTestCase {
  func testR14_02ThirtyTwoMiBFrameKeepsRSSBoundedAndThenAnswers() throws {
    let helper = try MCPProcessHarness()
    defer { helper.stop() }

    try helper.write(byte: 0x78, count: 32 * 1024 * 1024)
    let residentKiB = try helper.residentKiB()
    XCTAssertLessThan(residentKiB, 32 * 1024)

    try helper.write("\n" + #"{"jsonrpc":"2.0","id":2,"method":"ping"}"# + "\n")
    let response = try helper.response(id: 2, timeout: 1)
    XCTAssertNotNil(response["result"])
  }
}
