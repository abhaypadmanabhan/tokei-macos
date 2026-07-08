# Website TODO — 2026-07-08

No product website exists in/near the repo yet (checked: no `website/`, `site/`, `web/`,
`docs/site/`, no top-level HTML). When one is stood up, reflect this RC. Supersedes
`website-todo-2026-07-06.md`.

## Update on the next website build
- **Version:** 0.2.0 (once bumped) — feature release over the 0.1.0 MVP.
- **Supported providers + capability matrix** (headline: "tokens *and* quota, per agent"):
  - Codex — tokens + quota + estimated cost
  - Cursor — **tokens + live quota (new)**, opt-in online
  - Claude Code — tokens (quota coming)
  - Antigravity — live quota + credits (opt-in)
  - Cline — tokens + real $ cost
- **Feature highlights:** live utilization %, local-first (nothing leaves your machine unless
  you opt into a provider's online fetch), per-provider opt-in toggles, honest capability tiers.
- **Privacy copy:** all reads are of your own local files/accounts; provider online fetches are
  opt-in and authenticate with your own session; no telemetry.
- **Download link:** blocked on signing/notarization (currently adhoc/unsigned — not distributable).
- Required pages (from #10): landing, download, privacy policy, support, appcast host (Sparkle).

## Blocked on
- Signing/notarization (Developer ID) before any public download.
- Version bump decision (0.2.0).
