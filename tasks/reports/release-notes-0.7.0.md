## Tokei 0.7.0

**Tokei now talks to your other AI agents.** A bundled `tokei` CLI + MCP server lets
Claude Code, Codex, and other orchestrating agents check your remaining quota across
every tool before deciding where to route work — no more guessing which agent is
about to hit a wall.

### Added
- **Agent-facing quota snapshot + `tokei status` / `tokei mcp`** — a read-only helper
  bundled inside Tokei.app exposes your live quota (percentages, resets, confidence)
  to any local agent that asks, plus a routing recommendation ("route to Codex, avoid
  Antigravity — 92% used"). Register it once:

  ```sh
  claude mcp add tokei -- /Applications/Tokei.app/Contents/Helpers/tokei mcp
  ```

  You don't have to remember to ask. The server sends a standing instruction on
  connect telling the agent to check quota *before* it spawns or delegates, so the
  lookup happens on its own for the rest of the session.
- **GitHub Copilot** now shows up as a detected provider (install status only —
  Copilot doesn't expose local usage data yet, so no fabricated numbers).

### Fixed
- Hardened the local usage store against a crash mid-write, capped memory use on
  oversized Cline session files, and stopped a rare full-path leak in a warning
  message. None of these were user-visible bugs — just quiet robustness work.
- **Signing/notarization** — Sparkle's nested helpers and the new bundled `tokei`
  helper are now signed with Developer ID, a secure timestamp, and hardened runtime.
  This build is notarized and stapled; no Gatekeeper workaround needed.

_Requires macOS 14+ · Apple Silicon._
