## Tokei 0.7.0

**Tokei now talks to your other AI agents.** A bundled `tokei` CLI + MCP server lets
Claude Code, Codex, and other orchestrating agents check your remaining quota across
every tool before deciding where to route work — no more guessing which agent is
about to hit a wall.

### Added
- **Agent-facing quota snapshot + `tokei status` / `tokei mcp`** — a read-only helper
  bundled inside Tokei.app exposes your live quota (percentages, resets, confidence)
  to any local agent that asks, plus a routing recommendation ("route to Codex, avoid
  Antigravity — 92% used"). Register it with `claude mcp add tokei -- <path> mcp`.
- **GitHub Copilot** now shows up as a detected provider (install status only —
  Copilot doesn't expose local usage data yet, so no fabricated numbers).

### Fixed
- Hardened the local usage store against a crash mid-write, capped memory use on
  oversized Cline session files, and stopped a rare full-path leak in a warning
  message. None of these were user-visible bugs — just quiet robustness work.

### Known issue
- This build isn't notarized yet (unrelated packaging issue being tracked
  separately) — if you see a Gatekeeper warning on first launch, right-click →
  Open once to bypass it.

_Requires macOS 14+ · Apple Silicon._
