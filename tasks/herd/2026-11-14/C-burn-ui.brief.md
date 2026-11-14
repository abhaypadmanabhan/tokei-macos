# Brief WP-C · Burn UI + Mac smoothness (Claude Opus 5.5)

cd /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-ui — work ONLY in this directory (branch
`patch/2026-11-14/burn-ui`). The single exception: write your result file at the absolute path below, and proof
media under `~/Library/Developer/TokeiWork/proof/burn-ui/`.

## Read first (in this order)
1. `tasks/patch-bibles/2026-11-14.md` §"Abhay's answers", §3 shared rules, §4 contract, §5 WP-C (scope and
   acceptance; each AC names its check). That file is the spec; this brief adds logistics.
2. Load skills: `swift-swiftui`, `mac-design`, `mac-verify`, `mac-performance`. Design authority:
   `AIUsageDashboard/docs/07-padzy-theme.md` and `AIUsageDashboardApp/UI/Components/PadzyTheme.swift`
   (the padzy-os skill and the UI-UX vault notes are not on this Mac; do not look for them).
3. Your data API: `Core/Game/BurnSnapshot.swift`, `BurnSnapshot+Sample.swift` (`.sample(now:)`, `.empty(now:)`),
   `Core/Game/ExpiringHeadroom.swift`, `DashboardViewModel.burn`. WP-A fills `burn` in a parallel lane; until it
   merges, drive previews and a DEBUG-only launch flag (for example `-TokeiBurnSample YES`) from `.sample`.
4. Existing surfaces: `UI/MenuBar/*`, `UI/Dashboard/*`, `UI/Value/ValueView.swift`, `UI/Overview/*`, `UI/Settings/*`.

## Rules
- Before building, write in the result file the one detail that shows care (Premium App Craft), and check the
  transitions into and out of each new surface (launch, saved → live, tab switch, Settings), plus empty and error states.
- Measure before optimizing (AC 6): record the "before" numbers on the unmodified build first.
- Build/test: `cd AIUsageDashboard && xcodegen generate`; `-derivedDataPath ~/Library/Developer/TokeiWork/dd-burn-ui`;
  `-only-testing:` for the UI/Charts test classes you add or touch; a Release-config app build at the end;
  then `bash .claude/gates/run-all.sh fast` from the worktree root.
- Launching a built Tokei: only while holding the lock (`until mkdir /tmp/tokei-live-proof.lock 2>/dev/null; do sleep 5; done`,
  `rmdir /tmp/tokei-live-proof.lock` when done), quit the installed `/Applications/Tokei.app` first, and relaunch
  it (`open -a /Applications/Tokei.app`) when your proof session ends. Proof media may show usage numbers; they
  stay out of git.
- Do not edit `UI/Settings/AgentConnectSection.swift` (WP-B) or anything under `Core/` or `TokeiCLI/`. If you
  need a Core change, write it in the result file as a request; do not make it.
- Never `--no-verify`. No new dependencies.

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/C-burn-ui.result.md`:
line 1 `STATUS: READY` or `STATUS: BLOCKED`; the care detail; per AC (1–8): what you did, the check, exact
commands with output lines, proof file paths; the before/after numbers table; commits (`git log --oneline dev..HEAD`);
Core requests; known gaps. When complete, print exactly: `TOKEI_C_DONE`
