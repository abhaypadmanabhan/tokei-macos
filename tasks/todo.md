# Tokei 0.9.0 — accurate multi-account stats, CPU/RAM diet, account-aware MCP, UI declutter

Herd run: `~/.herd/runs/20260917-0209-eb/` (briefs in `briefs/`, results in `tasks/`).
Orchestrator: this session (cc1). Finding + planning: Codex Astra. Implementation: Codex Sol +
Cursor auto. Review: a different seat than the author, always.
Previous todo (0.8.0 multi-account, DONE 2026-07-29) archived — see git history.

Symptoms observed 2026-09-17T02:05Z, before any change (`tokei status --json`, pid 13882):
- `claude_code.accounts[default]` = `tokensToday 0`, `windows []`, no warning — signed-in Max account
- `claude_code.accounts[account-1]` = 534,780,586 tokens today, weekly 80% — is that number right?
- Tokei RSS **731 MB**, CPU spikes 32%, 15 min uptime
- `herd budget --route` cannot tell the two Claude accounts apart (both map to `claude_code`)

## Phase 1 — research (read-only, parallel)
- [x] t01 Astra — stats accuracy audit → `tasks/t01.result.md`
- [x] t02 Astra — CPU/RAM audit → `tasks/t02.result.md`
- [x] t03 Astra — MCP / snapshot / multi-account model → `tasks/t03.result.md`
- [x] t04 Cursor — UI clutter audit → `tasks/t04.result.md`

## Phase 2 — triage + Patch Bible
- [ ] Read all four results; rank `user_impact × release_value ÷ risk`
- [ ] Write `tasks/patch-bibles/2026-09-17.md`: ≤4 work packages, disjoint file scopes, merge order
- [ ] Worktrees from `dev` under `../tokei-worktrees/2026-09-17-<slug>` with the pre-commit hook

## Phase 3 — implement (Sol / Cursor, worktree isolation)
- [ ] WP-UI also: **animated live numbers** — every figure that refreshes (menu bar total, Overview totals, gauges, per-account rows, drill-in) transitions smoothly (SwiftUI `contentTransition(.numericText())` / interpolated rolling) instead of snapping; honours `accessibilityReduceMotion`; read `$UIUX_VAULT/Motion and Micro-interactions.md` first
- [x] WP per Bible (all four landed; WP-1/WP-2 partial only for full-corpus benches → reviewers); each ends with a result file + commits, tests green in its worktree
- [x] Reviewer on a different seat per WP — r07 MERGE; r05/r06/r08 BLOCK → fix rounds → r06b/r08b MERGE-WITH-FIXES (applied, diff-verified); r05b in flight

## Phase 4 — integrate (`/agents-done` steps, inline)
- [x] Quarantine gate, diff review, targeted tests, `--no-ff` merge — WP-3 `96ac609`, WP-2 `26dbdf4`, WP-4 `c8b192d`, WP-1 `75861c2`, D9 glue `4bf2a04`
- [x] `bash .claude/gates/run-all.sh full` on `dev` — build PASS, 558 tests / 0 failures; lint strict 380→360 (pre-existing debt)
- [x] Debug build; before/after on the same corpus: peak footprint 7,683 MB → 645 MB, RSS 3.0 GB → 0.3 GB, cold CPU 6:20 → 3:31, steady CPU 16.6 % → 12.1 % (Debug vs Release) — Bible §8

## Phase 5 — release (`/dev-approved`, inline)
- [ ] `/security-review` on `main...dev`, triage every finding
- [ ] `/simplify` pass, re-run build + test
- [ ] Real-corpus smoke tests (`*RealLogsSmokeTests`) opt-in via `TOKEI_REAL_LOGS=1` — default scheme burns ~3 CPU-min per run on this box (2026-09-17 hot-Mac report)
- [ ] Bump `MARKETING_VERSION` → 0.9.0, CHANGELOG, `docs/08` schema doc
- [ ] `scripts/release.sh` (sign, notarize, staple, DMG, appcast) — **ask before the outward steps**
- [ ] Website `website/lib/site.ts` version + download URL + highlights; deploy only when told

## Verify (real artifact)
- [ ] Both Claude accounts show correct, independently recomputed totals in the app and CLI
- [ ] `tokei status --json` + MCP expose per-account headroom a consumer can route on
- [ ] RSS/CPU measured before vs after on this machine's corpus (numbers in the Bible)
- [ ] Notarized DMG launches; Sparkle appcast valid; website shows 0.9.0
