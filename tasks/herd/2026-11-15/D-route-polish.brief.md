# Brief WP-D · `tokei route` reads like a person wrote it (Codex gpt-6.1-sol)

cd /Users/abhayp/wt/lane1 — work ONLY in this directory (branch `patch/2026-11-15/route-polish`, cut from `dev`
after WP-A and WP-B merged). Exception: your result file at the absolute path below.

Read `tasks/patch-bibles/2026-11-15.md` §3 and §4 first. Scope in: `AIUsageDashboard/TokeiCLI/RouteFormatting.swift`
(and the MCP text content if it shares the formatter), its tests, `Core/Utilization/RoutePlan.swift` reason
sentences only if needed. Scope out: everything else; the JSON output and the snapshot `route` block do not change.

Today the human output is:
```
Send the next task to Codex. Use this plan before unused capacity resets in 42m.
Codex: 62% left · fiveHour · resets in 41m · behind · ready
Cursor: 66% left · monthly · resets in 287h · behind · ready
```
Acceptance criteria (each with a test that fails on the current code):
1. Window names are words, the same ones `tokei burn` and `tokei status` print ("5-hour window", "weekly
   window", "monthly window"); no raw enum names anywhere in human or MCP text output.
2. Durations use the app's existing compact countdown (minutes under an hour, hours under two days, then days:
   "42 min", "18 h", "12 d"), from one helper already in the codebase if one exists; the headline and the row
   never disagree by a minute for the same row (compute once).
3. Pace and disposition read as plain words a user understands in a terminal: for example "under pace" /
   "on pace" / "ahead of pace", and rows to avoid say "avoid" while ready rows say nothing extra.
4. `--json` output is byte-identical to before for the same snapshot (test).
Run the CLI and MCP route test classes plus the existing CLI formatting classes with
`-derivedDataPath ~/Library/Developer/TokeiWork/dd-polish`, then `bash .claude/gates/run-all.sh fast`.
No merge, no push. Result: `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/D-route-polish.result.md`, line 1
`STATUS: READY` or `STATUS: BLOCKED`, per AC the test and red-then-green lines, the new sample output, commits.
Then run `hc send t1d "D result written"`.
