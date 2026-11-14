import Foundation
#if TOKEI_CLI_TESTS
import AIUsageDashboardCore
#endif

enum AgentCommands {
    struct MCPOptions: Equatable {
        let install: Bool
        let clients: [AgentClient]
        let dryRun: Bool
    }

    static func parseMCP(_ arguments: [String]) -> MCPOptions? {
        guard let verb = arguments.first, ["install", "uninstall"].contains(verb) else { return nil }
        var client = "all"
        var dryRun = false
        var seen = Set<String>()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted else { return nil }
            switch flag {
            case "--dry-run": dryRun = true
            case "--client":
                index += 1
                guard index < arguments.count else { return nil }
                client = arguments[index]
            default: return nil
            }
            index += 1
        }
        let clients = client == "all" ? AgentClient.allCases : AgentClient(rawValue: client).map { [$0] }
        guard let clients else { return nil }
        return MCPOptions(install: verb == "install", clients: clients, dryRun: dryRun)
    }

    static func mcp(_ arguments: [String]) -> Int32 {
        guard let options = parseMCP(arguments) else {
            print("Use tokei mcp install|uninstall [--client claude|codex|cursor|all] [--dry-run].")
            return 64
        }
        let connection = AgentConnection(helper: AgentConnection.runningHelper)
        var failed = false
        for client in options.clients {
            if options.clients.count > 1, !connection.stateDetectedWithoutReadingConfig(client) {
                print("\(client.name): not detected; skipped. Install the client to connect it.")
                continue
            }
            do { print(try connection.change(client, install: options.install, dryRun: options.dryRun)) }
            catch { print(error.localizedDescription); failed = true }
        }
        return failed ? 1 : 0
    }

    static func install(_ arguments: [String]) -> Int32 {
        guard arguments.isEmpty || arguments == ["--force"] else {
            print("Use tokei install [--force].")
            return 64
        }
        do {
            print(try AgentConnection(helper: AgentConnection.runningHelper).installCommand(force: !arguments.isEmpty))
            return 0
        } catch { print(error.localizedDescription); return 1 }
    }

    static func burn(reader: SnapshotReader = SnapshotReader()) -> Int32 {
        do { print(BurnFormatting.render(try reader.read(), now: reader.now())); return 0 }
        catch let error as SnapshotReadError { print(error.message); return error.exitCode }
        catch { print("tokei: \(error.localizedDescription)"); return 1 }
    }
}

private extension AgentConnection {
    func stateDetectedWithoutReadingConfig(_ client: AgentClient) -> Bool {
        if client == .cursor {
            return FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor").path)
                || FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
        }
        return binary(for: client) != nil
    }
}
