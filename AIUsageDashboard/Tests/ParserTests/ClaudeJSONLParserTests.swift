import XCTest
@testable import AIUsageDashboardCore

final class ClaudeJSONLParserTests: XCTestCase {
    var parser: ClaudeJSONLParser!
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        parser = ClaudeJSONLParser()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func writeFixture(_ content: String, named: String) -> URL {
        let url = tempDirectory.appendingPathComponent(named)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEmptyLogSources() async {
        let usage = await parser.parse(logSources: [])
        XCTAssertEqual(usage.lifetime.totalTokens, 0)
        XCTAssertEqual(usage.lifetime.confidence, .localParsed)
    }

    func testSampleJSONL() async throws {
        let content = """
        {"message_id": "msg_1", "timestamp": 1700000000, "usage": {"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 10}}
        {"message_id": "msg_2", "timestamp": 1700000001, "usage": {"input_tokens": 200, "output_tokens": 100, "cache_read_input_tokens": 30, "cache_creation_input_tokens": 15}}
        """
        let url = writeFixture(content, named: "sample.jsonl")
        let source = LogSource(providerID: .claudeCode, url: url, sessionID: "test-session")
        let usage = await parser.parse(logSources: [source])

        XCTAssertEqual(usage.lifetime.inputTokens, 300)
        XCTAssertEqual(usage.lifetime.outputTokens, 150)
        XCTAssertEqual(usage.lifetime.cacheReadTokens, 50)
        XCTAssertEqual(usage.lifetime.cacheCreationTokens, 25)
        XCTAssertEqual(usage.lifetime.totalTokens, 525)
    }

    func testDeduplication() async throws {
        let content = """
        {"message_id": "msg_1", "timestamp": 1700000000, "usage": {"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 10}}
        {"message_id": "msg_1", "timestamp": 1700000000, "usage": {"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 10}}
        """
        let url = writeFixture(content, named: "dup.jsonl")
        let source = LogSource(providerID: .claudeCode, url: url, sessionID: "test-session")
        let usage = await parser.parse(logSources: [source])
        XCTAssertEqual(usage.lifetime.inputTokens, 100)
    }
}

