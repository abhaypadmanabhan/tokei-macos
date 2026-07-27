# TOKEI BACKLOG

Single source of truth for future build work. When Abhay says "build the next
thing" (or names an item), pick from here — top of each tier first. Each item
lists enough context to start without re-research. Keep this file updated:
move finished items to DONE with date + commit.

## How agents should use this
1. Read this file + `tasks/relay/BATON.md` (protocol, frozen contracts, Padzy rules).
2. Confirm item scope with Abhay only if the item is marked [needs-decision].
3. Branch `feat/<slug>`, build+test green (`cd AIUsageDashboard && xcodegen generate` first), merge --no-ff, move the item to DONE here.

## P1 — high value, unblocked
- [ ] **WidgetKit target** — small/medium widgets showing today total + quota %.
      Needs App Group (`group.ai.padzy.tokei`) + UsageStore reading from the
      shared container; widget target added to project.yml. Deferred twice
      already for signing risk — do it in isolation.
- [ ] **Per-provider alert thresholds** — Settings UI (per provider row:
      80/95 defaults, editable) + NotificationEngine reads per-provider config
      from UserDefaults. Engine already has injectable evaluator.

## P2 — polish / depth
- [ ] **Daily history chart view** — UsageStore.dailyHistory() is persisted but
      unused by UI. Add a `03 / HISTORY` pane: 30-day bar chart per provider,
      Padzy style (hairline bars, accent = today).
- [ ] **Session drill-down** — per-session table (Dense tier) for the selected
      provider: session id, start, tokens, cost where known.
- [ ] **Launch at login** — SMAppService toggle in Settings.
- [ ] **CSV/JSON export** — export dailyHistory + snapshots from Settings.
- [ ] **Menu bar display options** — Settings: choose which providers count
      toward the menu bar total; compact vs percent display.
- [ ] **Sparkline hover** — hover a sparkline point → mono tooltip with date +
      exact tokens (macOS hover affordance).

## P3 — research / speculative
- [ ] **Antigravity token counts** — the connector ships (plan + credits offline,
      per-model quota via the app's local RPC), but Antigravity writes no local
      per-message log, so today/week tokens stay `unavailable`. Needs a new data
      source, not more parsing of `state.vscdb`.
- [ ] **Cline credits balance** — app.cline.bot internal API, undocumented.
      [needs-decision]
- [ ] **Multi-machine aggregation** — sync usage-store.json via iCloud Drive
      container; dedupe by day+provider.
- [ ] **App Store distribution** — the Developer ID half is done; this item is now only
      about the Mac App Store. Needs App Sandbox entitlements (the repo currently ships
      no `.entitlements` file and `project.yml` declares none) and a security-scoped
      bookmarks UX, because reading provider logs out of `~` won't survive the sandbox.
      [needs-decision: is the App Store worth the sandbox rework at all, given direct
      distribution already works?]

## DONE
- 2026-07-27 — **Release build launchability** (patch `patch/2026-07-27/release-signing`,
  `2ddec45` + `23897fd`): hardened runtime is now stated explicitly on
  `AIUsageDashboardCore`'s Release config instead of arriving as a side effect of the app's
  embed re-sign, and `build-app.sh` picks it per path — ON for `TOKEI_RELEASE=1`, forced OFF
  for ad-hoc dev builds. That pairing was the 2026-07-06 dyld failure: hardened runtime
  enables library validation, which demands a Team ID an ad-hoc signature does not carry.
  `scripts/verify-app.sh` now asserts a staged app can actually load, so an unlaunchable
  bundle can no longer exit 0.
- 2026-07-08 — **Developer ID signing + hardened runtime + notarization** (`966bebd`,
  Sparkle in `e5ff8a2`): `scripts/release.sh` submits via `notarytool`, polls, and staples
  both the app and the DMG; `scripts/make-dmg.sh` builds and signs the DMG. Shipped for real
  — 0.7.0 released notarized (`f787756`), 0.7.1 published a signed appcast (`a90fdd1`).
  Direct distribution is therefore complete; only Mac App Store sandboxing remains open.
- 2026-07-27 — **Quota trust gating + multi-account Claude Code** (dev @ `f725bac`):
  `routeTo` gated on trusted, recent readings while `avoid` still uses every reading;
  `observedAt` on every quota window; partially-expired caches return nothing rather than
  the loosest surviving window; `Retry-After` honoured without a retry storm; Claude Code
  discovered per `CLAUDE_CONFIG_DIR` (sibling `~/.claude-*` dirs holding `projects/`),
  tokens summed and headline quota taken from the account with most headroom.
- 2026-07-27 — **`tokei` CLI / MCP test coverage (#59)**: MCP stdio framing, `SnapshotReader`
  and `StatusFormatting` under the standard `AIUsageDashboardCore` scheme; README "What Is
  Stubbed" corrected against the provider code. 382 → 427 tests.
- 2026-07-08 — **Claude quota windows** (`7f18c85`): session/weekly limits via the opt-in
  OAuth usage endpoint (`ClaudeUsageClient`), `official` confidence, cooldown/cache handling.
- 2026-07-08 — **Codex cost estimate** (`9cce468`): static per-model pricing table,
  `.estimated` confidence; unknown model slugs yield no cost rather than a guessed number.
- 2026-07-06 — **Cursor real metrics (#3)** + **Antigravity data source (#4/#13)** connectors
  (patch Round 2, dev @ f78c1f8): Cursor A offline plan/tier + accepted-lines / B network
  quota behind `cursorNetworkUsageEnabled` toggle (default off); Antigravity offline protobuf
  (plan "Pro" + credits) via zero-dep `MiniProtobufReader` + `json_extract` (token never in
  memory); connection UX (per-provider show/hide toggles, honest capability tiers, local-path
  disclosure). 85 tests green, security pass (no credential leak vectors). Merges:
  dcfb832 (antigravity) · f78c1f8 (cursor) · fad1dd4 (connection-ux).
- 2026-07-06 — MVP: Claude parser + dashboard + menu bar + persistence +
  watcher (commit 1ccf4d1); Tokei rebrand + icon + hero UI (db5f421);
  Relay legs 1-4: Codex quotas, Cline cost, multi-provider UI, notifications
  (ff3b897, 4bdc594, 67017b0, cc3cb17); close-out 400c1e8. 59 tests.
