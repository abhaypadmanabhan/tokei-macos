import Foundation
import Darwin

/// The `tokei` helper exposes the quota snapshot and explicit local agent setup.
/// Snapshot commands and the MCP server read only the snapshot: no network or
/// Keychain. Install/uninstall commands change only the requested local registration.
///
///     tokei status          human-readable table
///     tokei status --json   raw snapshot JSON
///     tokei mcp             stdio MCP server (usage, routing, expiring plan capacity)
enum TokeiCLI {
    /// Must equal `MARKETING_VERSION` in AIUsageDashboard/project.yml. Hand-kept, so
    /// the `cli-version-sync` gate fails the commit when the two drift — this string
    /// silently reported 0.7.0 from a 0.7.1 build and cost real debugging time, because
    /// `tokei version` is the first thing you check when diagnosing which binary is live.
    static let version = "0.11.0"
}

func printUsage(to handle: FileHandle = .standardOutput) {
    let text = """
    tokei \(TokeiCLI.version) — agent-facing quota snapshot for Tokei

    USAGE:
      tokei status [--json]   Print the current usage snapshot (table, or raw JSON)
      tokei guard [--provider P] [--min-headroom N]  Exit 0 when fresh headroom meets N (default 15)
      tokei burn              Show expiring plan windows, today's goal and streak
      tokei mcp               Run the read-only stdio MCP server (3 tools)
      tokei mcp install [--client claude|codex|cursor|all] [--dry-run]
      tokei mcp uninstall [--client claude|codex|cursor|all] [--dry-run]
      tokei install [--force]  Put the bundled command in ~/.local/bin
      tokei help              Show this help
      tokei version           Print the version

    MCP tools: get_usage (optional detail: "summary"), get_route_recommendation,
    get_burn_opportunities. Connect from Settings → Connect agents, or use install.
    With --client all (the default), only detected clients are changed.

    The snapshot is written by the Tokei app after each refresh to
    ~/Library/Application Support/AIUsageDashboard/agent-snapshot.json.
    Launch Tokei at least once so the file exists.

    """
    handle.write(Data(text.utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "status":
    let wantsJSON = arguments.dropFirst().contains("--json")
    exit(StatusCommand.run(json: wantsJSON))
case "guard":
    exit(GuardCommand.run(arguments: Array(arguments.dropFirst())))
case "install":
    exit(AgentCommands.install(Array(arguments.dropFirst())))
case "burn":
    guard arguments.count == 1 else { printUsage(to: .standardError); exit(64) }
    exit(AgentCommands.burn())
case "mcp":
    if arguments.dropFirst().first.map({ ["install", "uninstall"].contains($0) }) == true {
        exit(AgentCommands.mcp(Array(arguments.dropFirst())))
    }
    signal(SIGPIPE, SIG_IGN)
    MCPServer(version: TokeiCLI.version).run()
    exit(0)
case "help", "--help", "-h":
    printUsage()
    exit(0)
case "version", "--version":
    print("tokei \(TokeiCLI.version)")
    exit(0)
case .some(let unknown):
    FileHandle.standardError.write(Data("tokei: unknown command '\(unknown)'\n".utf8))
    printUsage(to: .standardError)
    exit(64) // EX_USAGE
case .none:
    printUsage(to: .standardError)
    exit(64)
}
