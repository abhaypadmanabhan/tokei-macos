import XCTest
@testable import AIUsageDashboardCore

final class AgentConnectionTests: XCTestCase {
    var root: URL!
    var bin: URL!
    var helper: URL!

    override func setUpWithError() throws {
        root = try CLITestSupport.temporaryDirectory()
        bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        helper = root.appendingPathComponent("Tokei's app with spaces/tokei")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        for client in [AgentClient.claude, .codex] { try stub(client) }
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    var service: AgentConnection {
        AgentConnection(helper: helper, environment: ["HOME": root.path, "PATH": bin.path,
            "CLAUDE_CONFIG_DIR": root.appendingPathComponent("fake-claude").path,
            "CODEX_HOME": root.appendingPathComponent("fake-codex").path], fallbackDirectories: [])
    }

    func stub(_ client: AgentClient) throws {
        let source = #"""
        #!/usr/bin/python3
        import sys,os,json,pathlib
        home=pathlib.Path(os.environ['HOME'])
        client=pathlib.Path(sys.argv[0]).name
        assert os.environ['CLAUDE_CONFIG_DIR']==str(home/'fake-claude')
        assert os.environ['CODEX_HOME']==str(home/'fake-codex')
        state=home/(client+'.state.json')
        with (home/'calls.jsonl').open('a') as f: f.write(json.dumps([client]+sys.argv[1:])+'\n')
        args=sys.argv[1:]
        if args[:2]==['mcp','get']:
            if not state.exists():
                print('No MCP server named tokei');sys.exit(1)
            obj=json.loads(state.read_text())
            if client=='codex': print(json.dumps({'transport':obj}))
            else: print('Scope: User config (available in all your projects)\nCommand: '+obj['command']+'\nArgs: mcp')
        elif args[:2]==['mcp','add']:
            separator=args.index('--')
            state.write_text(json.dumps({'command':args[separator+1],'args':args[separator+2:]}))
        elif args[:2]==['mcp','remove']:
            state.unlink()
        else: sys.exit(2)
        """#
        let url = bin.appendingPathComponent(client.rawValue)
        try Data(source.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func calls() throws -> [[String]] {
        let data = try String(contentsOf: root.appendingPathComponent("calls.jsonl"))
        return try data.split(separator: "\n").map { try JSONDecoder().decode([String].self, from: Data($0.utf8)) }
    }

    func testClientCommandsAreLiteralScopedAndIdempotent() throws {
        for client in [AgentClient.claude, .codex] {
            XCTAssertTrue(try service.change(client, install: true).contains("connected tokei"))
            XCTAssertTrue(service.state(for: client).connected)
            XCTAssertTrue(try service.change(client, install: true).contains("already connected"))
            XCTAssertTrue(try service.change(client, install: false).contains("disconnected tokei"))
            XCTAssertTrue(try service.change(client, install: false).contains("already disconnected"))
        }
        let writes = try calls().filter { $0.contains("add") }
        XCTAssertEqual(writes, [
            ["claude", "mcp", "add", "--scope", "user", "tokei", "--", helper.path, "mcp"],
            ["codex", "mcp", "add", "tokei", "--", helper.path, "mcp"]
        ])
    }

    func testDryRunNeverExecutesClientsOrCreatesCursorConfig() throws {
        for client in AgentClient.allCases {
            XCTAssertTrue(try service.change(client, install: true, dryRun: true).hasPrefix("Would"))
            XCTAssertTrue(try service.change(client, install: false, dryRun: true).hasPrefix("Would"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("calls.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor").path))
    }

    func testClientOwnsExplicitCodexDirectoryCreation() throws {
        let config = root.appendingPathComponent("fake-codex")
        XCTAssertFalse(service.state(for: .codex).connected)
        _ = try service.change(.codex, install: false)
        _ = try service.change(.codex, install: true, dryRun: true)
        _ = try service.change(.codex, install: true)
        XCTAssertTrue(service.state(for: .codex).connected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path), "Tokei must not create or redirect client configuration directories")
    }

    func testDifferentClientRegistrationIsKept() throws {
        try Data(#"{"command":"/different/helper","args":["mcp"]}"#.utf8)
            .write(to: root.appendingPathComponent("codex.state.json"))
        XCTAssertThrowsError(try service.change(.codex, install: true))
        XCTAssertFalse(try calls().contains { $0.contains("add") || $0.contains("remove") })
    }

    func testClientFailureDoesNotPrintChildDiagnostics() throws {
        let url = bin.appendingPathComponent("codex")
        try Data("#!/bin/sh\necho 'private diagnostic'\nexit 1\n".utf8).write(to: url)
        XCTAssertThrowsError(try service.change(.codex, install: true)) { error in
            XCTAssertFalse(error.localizedDescription.contains("private diagnostic"))
            XCTAssertTrue(error.localizedDescription.contains("could not read"))
        }
    }

    func testCursorMergeBackupOnceAtomicAndUninstallPreservesOtherServers() throws {
        let directory = root.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mcp.json")
        let original = Data(#"{"mcpServers":{"other":{"command":"keep"}},"custom":42}"#.utf8)
        try original.write(to: url)
        XCTAssertTrue(try service.change(.cursor, install: true).contains("connected tokei"))
        let backup = directory.appendingPathComponent("mcp.json.bak")
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let installed = try Data(contentsOf: url)
        XCTAssertTrue(try service.change(.cursor, install: true).contains("already connected"))
        XCTAssertEqual(try Data(contentsOf: url), installed)
        XCTAssertTrue(try service.change(.cursor, install: false).contains("disconnected tokei"))
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(result["custom"] as? Int, 42)
        let servers = try XCTUnwrap(result["mcpServers"] as? [String: [String: String]])
        XCTAssertEqual(servers, ["other": ["command": "keep"]])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testInvalidCursorJSONIsNeverReplacedOrBackedUp() throws {
        let directory = root.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mcp.json")
        for text in ["{invalid", "[]", #"{"mcpServers":[]}"#] {
            try Data(text.utf8).write(to: url)
            XCTAssertThrowsError(try service.change(.cursor, install: true))
            XCTAssertEqual(try String(contentsOf: url), text)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".bak"))
        }
    }

    func testInstallCommandRefusesOtherTargetsAndForceReplacesOnlyFile() throws {
        XCTAssertTrue(try service.installCommand().contains("Installed"))
        XCTAssertTrue(try service.installCommand().contains("already installed"))
        let link = root.appendingPathComponent(".local/bin/tokei")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), helper.path)
        try FileManager.default.removeItem(at: link)
        try Data("keep".utf8).write(to: link)
        XCTAssertThrowsError(try service.installCommand())
        XCTAssertEqual(try String(contentsOf: link), "keep")
        XCTAssertTrue(try service.installCommand(force: true).contains("export PATH="))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: true)
        XCTAssertThrowsError(try service.installCommand(force: true))
    }

    func testFindsLocalBinWithoutShellPATH() throws {
        let local = root.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bin.appendingPathComponent("claude"), to: local.appendingPathComponent("claude"))
        let fallback = AgentConnection(helper: helper, environment: ["HOME": root.path, "PATH": ""], fallbackDirectories: [])
        XCTAssertEqual(fallback.binary(for: .claude)?.path, local.appendingPathComponent("claude").path)
    }
}
