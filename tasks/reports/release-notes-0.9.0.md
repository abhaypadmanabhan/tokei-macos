## [0.9.0] — 2026-09-17 (release candidate)

On `dev`; **not yet merged to `main` or tagged.** Build 9. Audit trail:
`tasks/patch-bibles/2026-09-17.md` (four research audits → six work packages → reviews on a
different seat than each author; every finding, fix round and verdict is logged in §8 and in
herd run `20260917-0209-eb`). Automated QA: 618 Core tests green; the Debug app was launched
against the live corpus and the account-aware snapshot read back through the new helper.
Manual click-through of every SwiftUI state was not performed.

### Fixed — the numbers
- **Nested Claude Code subagent logs were never counted.** Discovery looked one directory
  deep; 206 nested session files on this machine were invisible. On the audited corpus that was
  −70 M tokens for one account's day and −761 M lifetime across accounts. Discovery is now a
  recursive regular-file walk.
- **The same session file living under two Claude config directories was counted twice**
  (363 messages, 159.5 M tokens in week/month/lifetime). Dedupe is now provider-wide with a
  deterministic per-account allocation and an explicit ambiguity warning; provider totals are
  unique, account rows are disjoint and sum to them.
- **A message whose output count grew across records kept its first, smaller value.** Records
  are reconciled (subtract previous, add updated); identical copies still dedupe.
- **Append cache could freeze a wrong total:** an unfinished trailing JSON line was consumed and
  the offset advanced past it; a same-size rewrite took the append path and kept the old
  aggregate. The tail is retained until complete and appends require inode + tail continuity.
- **Today's window had no upper bound**, so a clock-skewed record dated tomorrow counted today.
- **Codex counted repeated telemetry snapshots as new usage** (+242 K on the audit day, +78 M
  over history): an unchanged cumulative usage vector adds zero tokens; resets and resumed
  sessions are handled explicitly.
- **Cursor "accepted lines" leaked into token charts** in the offline path. Unknown token
  history is now unavailable rather than a different metric wearing the wrong label.
- **opencode read only the main SQLite file and missed committed WAL rows** (305 K tokens on the
  frozen fixture). Reads are coherent (online backup, WAL-aware) and cached for unchanged inputs.
- **"This week" was seven rolling days; "month" was a calendar month while the chart was 30
  days.** Labels say "Last 7 days"; month is the trailing 30 days everywhere.
- **The menu-bar total ignored "show in totals"; a today headline carried a 30-day delta.**

### Changed — CPU and memory
Whole-app, same machine, same live corpus, cold launch, 8-minute settle:
**peak physical footprint 7,683 MB → 645 MB; RSS after settle 3.0 GB → 0.3 GB; CPU to first
sync 6 min 20 s → 3 min 31 s; steady-state CPU 16.6 % → 12.1 % of a core (Debug build vs the
0.8.0 Release build).** Parser-level, independently re-measured by a reviewer on frozen copies:
Codex 826 files 121.6 s / 3.0 GB → 36–40 s / 176–185 MiB; Claude 1,722 files cold peak 2.2 GB →
107–121 MiB, warm refresh 330 ms → 3–60 ms. Mechanisms: chunk-scoped autorelease in both stream
loops, linear tail scanning, a cached reconciled allocation, discovery-time file metadata, no
opencode reparse when nothing changed, memoized Codex model detection, one SQLite snapshot per
refresh, and the status strip stops ticking while the window is hidden.

### Added — accounts are first-class, for any provider
- **`ProviderAccount`**: identity key `provider:sha256(provider ∥ quotaIdentity)` (local-root
  fallback when a provider exposes no identity), discovery on every refresh (new root, removed
  root, identity switch), Claude and **Codex** adapters (`CODEX_HOME` roots, identity from
  `tokens.account_id`, per-root cache isolation, per-session-file ownership across a re-login).
- **One quota decision** (trusted + fresh + complete coverage, peak-first) shared by the
  provider headline and the recommendation; the three copies of that logic are gone.
- **Agent snapshot / CLI / MCP (additive, `schemaVersion` still 1):** `accounts[].accountID`,
  `selector.env` (`CLAUDE_CONFIG_DIR` / `CODEX_HOME` as a literal environment map — never a
  shell string), `quota{status, usedPercent, headroomPercent, bindingWindowIndex, validUntil}`
  with bounded reason codes (`expiredCredentials`, `cooldown`, …), provider `headlineAccountID`,
  `recommendation.target{provider, accountID, selector}`, `avoidAccounts`, `validUntil`. The
  helper drops an expired recommendation on read and says why; `tokei status` lists every
  account and its quota state. Docs 06/08/09 and the README describe the shape; ship the helper
  and the app together (an old helper in front of a new app is a lossy proxy).
- **MCP transport**: JSON-RPC error classes are right (−32700 only for malformed JSON, −32600
  invalid request, −32601 unknown method, −32602 unknown tool / bad arguments — validated before
  any disk read); notifications are silent; batches are rejected explicitly.
- **Live numbers roll.** Every figure that changes on refresh transitions with a 220 ms
  numeric roll; bars interpolate; Reduce Motion snaps.

### Removed — UI
Pressure banner, circular gauge, usage donut, weekday bars, activity heatmap, sparkline,
duplicate breadcrumb/last-sync/capability/badge text, Value insight box and TOTAL row, Settings
theme row / feedback placeholder / agents shortcut, coloured status dots, the raw malformed-file
banner on every tab (warnings are a collapsed disclosure on the drill-in, bounded to 8 × 200
chars). Net −1.4 k lines of UI.

### Known
- The default Claude account on the author's machine has an expired OAuth token; Tokei never
  refreshes tokens (that would race the CLI's own rotation). Its row reads `expiredCredentials`
  until `claude` is run once from that directory.
- A Codex session that straddles a re-login within one file is attributed to the identity it
  started under.
- Strict SwiftLint is still red globally (360 violations, down from 380 in 0.8.0).

