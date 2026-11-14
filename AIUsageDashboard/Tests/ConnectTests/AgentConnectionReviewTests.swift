import XCTest
@testable import AIUsageDashboardCore

final class AgentConnectionReviewTests: XCTestCase {
    var root: URL!
    var bin: URL!
    var helper: URL!

    override func setUpWithError() throws {
        root = try CLITestSupport.temporaryDirectory()
        bin = root.appendingPathComponent("bin")
        helper = root.appendingPathComponent("Tokei.app/Contents/Helpers/tokei")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        for client in ["claude", "codex"] {
            let script = bin.appendingPathComponent(client)
            try Data(Self.stub.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    var service: AgentConnection {
        AgentConnection(helper: helper, environment: ["HOME": root.path, "PATH": bin.path], fallbackDirectories: [])
    }

    static let stub = #"""
    #!/usr/bin/python3
    import os,sys,json,pathlib
    home=pathlib.Path(os.environ['HOME'])
    name=pathlib.Path(sys.argv[0]).name
    args=sys.argv[1:]
    (home/'environment.json').write_text(json.dumps({key:os.environ.get(key) for key in ['CLAUDE_CONFIG_DIR','CODEX_HOME','PATH']}))
    with (home/'calls.jsonl').open('a') as f: f.write(json.dumps(args)+'\n')
    state=home/(name+'.json')
    if args[:2]==['mcp','get']:
        if not state.exists(): print('No MCP server named tokei');sys.exit(1)
        obj=json.loads(state.read_text())
        if name=='codex': print(json.dumps({'transport':obj}))
        else:
            scope='Local config (private to you in this project)' if obj.get('scope')=='local' else 'User config (available in all your projects)'
            print('Scope: '+scope+'\nCommand: '+obj['command']+'\nArgs: mcp')
    elif args[:2]==['mcp','add']:
        i=args.index('--')
        state.write_text(json.dumps({'command':args[i+1],'args':args[i+2:]}))
    elif args[:2]==['mcp','remove']: state.unlink()
    else: sys.exit(2)
    """#

    func environment() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("environment.json"))) as? [String: Any])
    }

    func cursorFile(_ text: String) throws -> URL {
        let url = root.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testS1AbsentProfileVariablesStayAbsentInChildren() throws {
        for client in [AgentClient.claude, .codex] {
            _ = try service.change(client, install: true)
            let child = try environment()
            XCTAssertTrue(child["CLAUDE_CONFIG_DIR"] is NSNull)
            XCTAssertTrue(child["CODEX_HOME"] is NSNull)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex").path))
    }

    func testS1ExplicitProfileVariablesPassThroughUnchanged() throws {
        let env = ["HOME": root.path, "PATH": bin.path,
                   "CLAUDE_CONFIG_DIR": root.appendingPathComponent("chosen-claude").path,
                   "CODEX_HOME": root.appendingPathComponent("chosen-codex").path]
        let selected = AgentConnection(helper: helper, environment: env, fallbackDirectories: [])
        _ = try selected.change(.claude, install: true)
        let child = try environment()
        XCTAssertEqual(child["CLAUDE_CONFIG_DIR"] as? String, env["CLAUDE_CONFIG_DIR"])
        XCTAssertEqual(child["CODEX_HOME"] as? String, env["CODEX_HOME"])
    }

    func testS2CursorSymlinkAndIndependentByteBackupSurvive() throws {
        let original = Data(#"{"mcpServers":{"other":{"command":"keep"}}}"#.utf8)
        let target = root.appendingPathComponent("dotfiles/mcp.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let link = root.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../dotfiles/mcp.json")
        _ = try service.change(.cursor, install: true)
        XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "../dotfiles/mcp.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any])
        XCTAssertNotNil((object["mcpServers"] as? [String: Any])?["tokei"])
        let backup = URL(fileURLWithPath: link.path + ".bak")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup.path)[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        _ = try service.change(.cursor, install: false)
        XCTAssertEqual(try Data(contentsOf: backup), original, "backup must not follow later target changes")
        XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "../dotfiles/mcp.json")
    }

    func testS3DifferentCursorRegistrationAndExistingBackupAreKept() throws {
        let text = #"{"mcpServers":{"tokei":{"command":"/other/tokei","args":["mcp"],"env":{"TOKEI_SNAPSHOT_PATH":"/custom/path"}}}}"#
        let url = try cursorFile(text)
        let backup = URL(fileURLWithPath: url.path + ".bak")
        try Data("earlier backup".utf8).write(to: backup)
        XCTAssertThrowsError(try service.change(.cursor, install: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Disconnect it first"))
        }
        XCTAssertEqual(try String(contentsOf: url), text)
        XCTAssertEqual(try String(contentsOf: backup), "earlier backup")
    }

    func testS4ClaudeLocalScopeIsNotUserConnectedOrRemoved() throws {
        let data = try JSONSerialization.data(withJSONObject: ["command": helper.path, "args": ["mcp"], "scope": "local"])
        let state = root.appendingPathComponent("claude.json")
        try data.write(to: state)
        XCTAssertFalse(service.state(for: .claude).connected)
        XCTAssertThrowsError(try service.change(.claude, install: true))
        XCTAssertThrowsError(try service.change(.claude, install: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("claude mcp remove tokei -s local"))
        }
        XCTAssertEqual(try Data(contentsOf: state), data)
        let calls = try String(contentsOf: root.appendingPathComponent("calls.jsonl"))
        XCTAssertFalse(calls.contains("remove"))
    }

    func testS5ConfigNotFoundIsAnErrorRatherThanDisconnected() throws {
        let script = bin.appendingPathComponent("claude")
        try Data("#!/bin/sh\necho 'Claude configuration file not found'\nexit 1\n".utf8).write(to: script)
        XCTAssertNotNil(service.state(for: .claude).message)
        XCTAssertThrowsError(try service.change(.claude, install: false))
    }

    func testS6FoundBinaryAndFallbackDirectoriesLeadChildPATH() throws {
        let local = root.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bin.appendingPathComponent("claude"), to: local.appendingPathComponent("claude"))
        let fallback = root.appendingPathComponent("fallback/bin").path
        let selected = AgentConnection(helper: helper, environment: ["HOME": root.path, "PATH": "/usr/bin:/bin"],
                                       fallbackDirectories: [fallback])
        _ = try selected.change(.claude, install: true)
        XCTAssertEqual(try environment()["PATH"] as? String, local.path + ":" + fallback + ":/usr/bin:/bin")
    }

    func testS7CursorJSONKeepsReadableSlashes() throws {
        let url = try cursorFile(#"{"mcpServers":{"other":{"command":"/some/path"}}}"#)
        _ = try service.change(.cursor, install: true)
        XCTAssertFalse(try String(contentsOf: url).contains(#"\/"#))
    }

    func testS9TemporaryAppLocationsCannotConnectOrInstall() throws {
        for path in ["/Volumes/Tokei/Tokei.app/Contents/Helpers/tokei",
                     "/private/var/folders/test/AppTranslocation/uuid/d/Tokei.app/Contents/Helpers/tokei"] {
            let temporary = AgentConnection(helper: URL(fileURLWithPath: path),
                environment: ["HOME": root.path, "PATH": bin.path], fallbackDirectories: [])
            for action in [{ try temporary.change(.cursor, install: true) }, { try temporary.installCommand() }] {
                XCTAssertThrowsError(try action()) { error in
                    XCTAssertTrue(error.localizedDescription.contains("Move Tokei to Applications, then retry"))
                }
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor/mcp.json").path))
    }

    func testS10SettingsInstallOmitsShellPATHHint() throws {
        let message = try service.installCommand(includePATHHint: false)
        XCTAssertFalse(message.contains("PATH"))
        XCTAssertFalse(message.contains("export"))
        XCTAssertTrue(try service.installCommand().contains("export PATH="), "terminal keeps its actionable hint")
    }
}
