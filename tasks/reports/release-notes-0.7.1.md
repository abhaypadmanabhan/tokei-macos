## Tokei 0.7.1

**Fixes MCP.** If you registered Tokei with Claude Code or Codex on 0.7.0, it never
connected. Update and it will.

### Fixed
- **MCP server rejected every current client.** `claude mcp add tokei …` reported
  success and then always failed with `✘ Failed to connect — -32602: Unsupported
  protocol version 2025-11-25`. Claude Code negotiates a newer protocol revision than
  0.7.0's server would accept, and the server errored instead of replying with the
  version it does support — which is what MCP version negotiation actually asks for.
  Now verified against the real client: `claude mcp list` reports `✔ Connected`.
- **`tokei version` reported the wrong version.** The bundled CLI printed `0.7.0` from
  a 0.7.1 build because the string was hardcoded rather than tracking the app version.
  It's the first thing you check when working out which binary is live, so the drift
  actively misled debugging. A build gate now fails when the two disagree.

### Unaffected on 0.7.0
`tokei status` and `tokei status --json` worked correctly throughout — only the MCP
transport was broken. If you were using the CLI directly or the `CLAUDE.md` steering
rule, nothing changed for you.

### Verifying it worked
Registration reporting success is not proof of a connection. After updating:

```sh
claude mcp list
```

Look for `tokei … ✔ Connected`.

_Requires macOS 14+ · Apple Silicon. Signed and notarized._
