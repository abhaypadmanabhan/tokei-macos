VERDICT: CHANGES

S1 [should] AIUsageDashboard/AIUsageDashboardApp/UI/Burn/BurnView.swift:55 A new celebration is consumed while Burn is covered by an agent detail. Reading: open an agent from Burn, then receive a record/tier moment. DashboardView.swift:171–181 intentionally keeps the Burn pane mounted under the opaque detail; BurnView still passes the celebration to the hero, and CelebrationModifier.play finishes it and clears the board. Returning to Burn therefore misses the one-shot reward. Fix: pass an explicit active/uncovered state from the dashboard and defer playback/consumption until Burn is actually exposed; cover that state in the celebration check.

S2 [should] AIUsageDashboard/AIUsageDashboardApp/UI/Burn/ShareCardView.swift:155 The displayed share card and exported PNG can disagree after a live refresh. Reading: leave Share my week open while usage changes. BurnView.swift:40 supplies a model from the current snapshot, so the preview follows the new card, but this appearance-only task leaves `png` cached from the earlier card; Copy and Save prefer that old data at lines 172 and 183. Fix: freeze the card model when opening the sheet, or invalidate/regenerate the PNG whenever the card changes.

Reviewed branch `patch/2026-11-14/burn-ui`, HEAD `10ded0685e196d0540b75f52058f04c03ca03754`, merge-base with dev `a490828ab056b6d2634e434d75c0a3b6cf3a3104`. No source edits, commits, subagents, or Tokei launches/quits/copies. Both findings are code reading, not live reproductions.

Commands and results

- `shasum -a 256 /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-14/C-review.brief.md` — exit 0; matched `5c166cacaee35fe19b1b9180e50bfec461f2a3a09ef3781971b690a5b2823223` before reading the brief.
- `git merge-base HEAD dev`, `git diff $(git merge-base HEAD dev)`, `git status --short`, `git rev-parse HEAD` — exit 0; inspected the changed paths and callers; worktree clean before and after checks.
- From `AIUsageDashboard/`, `xcodegen generate` — exit 0.

```sh
xcodebuild -project AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardCore -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-review-c \
  -only-testing:AIUsageDashboardCoreTests/BurnBoardTests \
  -only-testing:AIUsageDashboardCoreTests/BurnContrastTests \
  -only-testing:AIUsageDashboardCoreTests/BurnCopyTests \
  -only-testing:AIUsageDashboardCoreTests/MenuBarLabelModelTests \
  -only-testing:AIUsageDashboardCoreTests/ShareCardModelTests \
  -only-testing:AIUsageDashboardCoreTests/AccountSeriesStyleTests \
  -only-testing:AIUsageDashboardCoreTests/NoEyebrowTextTests test
```

Exit 0: 34 selected tests passed, zero failures. Log: `/tmp/tokei-c-review-r1-tests.log`. No full-suite run.

```sh
xcodebuild -project AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardApp -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-review-c build
```

Exit 0: BUILD SUCCEEDED. Log: `/tmp/tokei-c-review-r1-release.log`. Compiler warnings occur in paths outside this lane; no baseline build was run, so they are not classified as pre-existing.

- `BASE_REF=$(git merge-base HEAD dev) bash .claude/gates/run-all.sh fast` — exit 0. Formatting and lint checks SKIPPED because swiftformat and swiftlint are not installed. Log: `/tmp/tokei-c-review-r1-fast.log`.
- `/Users/abhayp/agent-kit/bin/secscan /Users/abhayp/src/tokei-worktrees/2026-11-14-burn-ui` — exit 0. `VERDICT: PASS`; no FLAG or GAP lines. Log: `/tmp/tokei-c-review-r1-secscan.log`.
- Python read-only Release binary check for `TokeiBurnSample`, `TokeiBurnEmpty`, `TokeiBurnMoment`, `TokeiReduceMotion`, `TokeiShareCardOut`, `TokeiProofRoute`, and `TokeiProofVisible` — exit 0; output `Release debug flag strings: []`. Source call sites are guarded by DEBUG.
- `lsof -nP -iTCP -sTCP:LISTEN` — exit 0; no listener or background job started by this review remains.

Not checked live, as instructed: menu dropdown opening and Burn navigation; light/dark sample and genuine empty states; saved-to-live layout stability; celebrations, Reduce Motion, focus and pointer stability; actual Copy/Save PNG output and its size; keyboard menu behavior; VoiceOver; launch/menu latency, five-minute open/closed idle CPU, and scrolling/tab hitches. The author's C-burn-ui.result.md was absent at review time, so no completed before/after performance table or UI proof was available there to assess.

Waits on: the Burn UI author for S1/S2 fixes and live proof.
