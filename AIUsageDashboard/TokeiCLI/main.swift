import Foundation

/// The `tokei` helper — a read-only companion to the Tokei app that exposes the quota
/// snapshot to orchestrating agents (issue #57). It reads ONLY the snapshot file: no
/// network, no Keychain, no other apps' files.
///
///     tokei status          human-readable table
///     tokei status --json   raw snapshot JSON
///     tokei mcp             stdio MCP server (tools: get_usage, get_route_recommendation)
enum TokeiCLI {
    /// Must equal `MARKETING_VERSION` in AIUsageDashboard/project.yml. Hand-kept, so
    /// the `cli-version-sync` gate fails the commit when the two drift — this string
    /// silently reported 0.7.0 from a 0.7.1 build and cost real debugging time, because
    /// `tokei version` is the first thing you check when diagnosing which binary is live.
    static let version = "0.7.1"
}

func printUsage(to handle: FileHandle = .standardOutput) {
    let text = """
    tokei \(TokeiCLI.version) — agent-facing quota snapshot for Tokei

    USAGE:
      tokei status [--json]   Print the current usage snapshot (table, or raw JSON)
      tokei mcp               Run the stdio MCP server (2 tools: get_usage, get_route_recommendation)
      tokei help              Show this help
      tokei version           Print the version

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
case "mcp":
    MCPServer().run()
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
