VERDICT: APPROVE

No outstanding findings. S1 from round 1 is resolved by 8572071: the ranked row remains unchanged, both chips use one shared human-policy visibility gate, and a visible chip can only name the row's recommendation. Equal and nearly spent plans remain quiet; a clear spread still shows the chip. No new blocker, should or nit finding in the author's changes.

Scope: reviewed 8572071 (6 files, 65 insertions/12 deletions) since round-1 HEAD 17027c2. Current HEAD is ad0e55bf8d4dee5201f156d8cbf5db8f1ac8339f. The subsequent ad0e55b merge imports dev's CLI polish and run records without changing app/UI source; those imported changes are not attributed to the author. HEAD and clean status were checked again after verification and were unchanged. No source edits, commits, app launches, installed-app copies or quits.

## Commands and exit codes

1. In `/Users/abhayp/wt/lane2/AIUsageDashboard`, `xcodegen generate` — exit 0, project generated.

2. Covering tests, one invocation — exit 0:

```sh
cd /Users/abhayp/wt/lane2/AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardCore -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui \
  -only-testing:AIUsageDashboardCoreTests/DemoFixtureTests \
  -only-testing:AIUsageDashboardCoreTests/RouteSuggestionTests \
  -only-testing:AIUsageDashboardCoreTests/SecondTickerTests \
  -only-testing:AIUsageDashboardCoreTests/WP4LabelMotionTests \
  -only-testing:AIUsageDashboardCoreTests/NoEyebrowTextTests \
  -only-testing:AIUsageDashboardCoreTests/RoutePlanTests \
  -only-testing:AIUsageDashboardCoreTests/RouteTargetPolicyTests \
  -only-testing:AIUsageDashboardCoreTests/BurnBoardTests \
  -only-testing:AIUsageDashboardCoreTests/MenuBarLabelModelTests \
  -only-testing:AIUsageDashboardCoreTests/SavedSnapshotLaunchTests \
  -only-testing:AIUsageDashboardCoreTests/AgentRouteSnapshotTests \
  -only-testing:AIUsageDashboardCoreTests/RouteCommandTests \
  CODE_SIGNING_ALLOWED=NO test \
  > /Users/abhayp/Library/Developer/TokeiWork/review-route-ui-r2-tests.log 2>&1
```

```text
Executed 93 tests, with 0 failures (0 unexpected) in 4.030 (4.063) seconds
** TEST SUCCEEDED **
```

All 16 RouteSuggestionTests passed, including testTwoEqualPlansGetARecommendationButNoChip, testNearlySpentPlansOnePointApartGetNoChip, testAClearSpreadPutsTheChipOnTheRowsPlan and testOnePlanGetsNoChip. All five DemoFixtureTests passed, including the new assertion that the fixture's chip remains Codex. No tests weakened or removed.

3. Release app build — exit 0:

```sh
cd /Users/abhayp/wt/lane2/AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardApp -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui \
  CODE_SIGNING_ALLOWED=NO build \
  > /Users/abhayp/Library/Developer/TokeiWork/review-route-ui-r2-release.log 2>&1
```

Actual output: `** BUILD SUCCEEDED **`. Chart deprecation warnings and an AppIntents metadata notice remain; these also appeared in the round-1 build. No app launch.

4. Independent synthetic probe of the actual RouteCopy helper and built Core framework — exit 0:

```sh
cd /Users/abhayp/wt/lane2
python3 - <<'PYPROBE'
from pathlib import Path
import os, subprocess
source = Path('AIUsageDashboard/AIUsageDashboardApp/UI/Components/RouteCopy.swift').read_text()
probe = r'''
let reference = Date(timeIntervalSince1970: 1794582000)
func sample(_ id: ProviderID, used: Double) -> ProviderSnapshot {
    ProviderSnapshot(providerID: id, displayName: id.rawValue, authStatus: .authenticated,
        quotaWindows: [QuotaWindow(providerID: id, type: .weekly, used: used, limit: 100,
            remaining: 100 - used, resetAt: reference.addingTimeInterval(3 * 86400),
            confidence: .providerReported, source: "review synthetic", observedAt: reference,
            windowDuration: 7 * 86400)], todayUsage: .unavailable, weekUsage: .unavailable)
}
let cases: [(String, [ProviderSnapshot], ProviderID?)] = [
    ("one", [sample(.claudeCode, used: 30)], nil),
    ("equal", [sample(.claudeCode, used: 30), sample(.codex, used: 30)], nil),
    ("one-point-spread", [sample(.claudeCode, used: 30), sample(.codex, used: 31)], nil),
    ("nearly-spent", [sample(.claudeCode, used: 83), sample(.codex, used: 84)], nil),
    ("clear-spread", [sample(.claudeCode, used: 72), sample(.codex, used: 20)], .codex),
    ("ceiling", [sample(.claudeCode, used: 75), sample(.codex, used: 95)], nil)
]
for (label, snapshots, expected) in cases {
    let plan = RoutePlan.make(snapshots: snapshots, now: reference)
    let suggestion = RouteSuggestion.make(plan, snapshots: snapshots, now: reference)
    let chip = RouteSuggestion.chipTarget(suggestion, utilizations: UtilizationEngine.utilizations(from: snapshots), now: reference)
    precondition(chip == expected, "unexpected chip for \(label)")
    precondition(chip == nil || chip == suggestion.target, "chip differs from row")
    print("\(label): row=\(suggestion.target?.rawValue ?? "nil") chip=\(chip?.rawValue ?? "nil") PASS")
}
'''
folder='/Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui/Build/Products/Debug'
r=subprocess.run(['swift','-F',folder,'-framework','AIUsageDashboardCore','-'],input=source+probe,env=dict(os.environ,DYLD_FRAMEWORK_PATH=folder),text=True)
raise SystemExit(r.returncode)
PYPROBE
```

```text
one: row=nil chip=nil PASS
equal: row=claude_code chip=nil PASS
one-point-spread: row=claude_code chip=nil PASS
nearly-spent: row=claude_code chip=nil PASS
clear-spread: row=codex chip=codex PASS
ceiling: row=claude_code chip=nil PASS
```

5. Release demo exclusion, `strings -a` on the rebuilt app executable and embedded Core framework, orchestrated by this Python command — exit 0:

```sh
python3 - <<'PYSTRINGS'
from pathlib import Path
import subprocess
root=Path('/Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui/Build/Products/Release/Tokei.app/Contents')
terms=['DemoFixture','TokeiProofFixture','TokeiDemoRoute','TokeiProofTickReport','TokeiProofRouteExpanded','demo fixture']
for file in [root/'MacOS/Tokei',root/'Frameworks/AIUsageDashboardCore.framework/AIUsageDashboardCore']:
    r=subprocess.run(['strings','-a',str(file)],capture_output=True,text=True,check=True)
    counts={term:sum(term in line for line in r.stdout.splitlines()) for term in terms}
    print(str(file.relative_to(root))+': '+str(counts))
    assert all(count==0 for count in counts.values())
PYSTRINGS
```

All six terms returned 0 in both binaries. No fixture, timer, VoiceOver, keyboard or Reduce Motion implementation changed in this fix round.

6. `bash .claude/gates/run-all.sh fast > /Users/abhayp/Library/Developer/TokeiWork/review-route-ui-r2-gates.log 2>&1` — exit 0, ALL GATES GREEN. Format/lint explicitly SKIP because swiftformat/swiftlint are not installed. No-secret reports an empty staged diff; this is not a branch secscan.

7. Static checks / scope:

- `git show --format= 8572071` and its stat; `git diff --stat ad0e55b^1 ad0e55b`; `git log --oneline --decorate 17027c2..HEAD` — exit 0, used to distinguish the author's fix from imported dev changes.
- `git diff 8572071..HEAD -- AIUsageDashboard/AIUsageDashboardApp` — exit 0, empty: the merge changes no app source.
- `git diff --check 17027c2..8572071` — exit 0, no output for the author's fix.
- `git diff --check 17027c2..HEAD` — exit 2 for only `tasks/herd/2026-11-15/W-review-r1.md:101: new blank line at EOF`. Baseline command `git diff --check 17027c2..f5b926d` gives the identical exit 2/output, establishing this comes from dev's imported run record. Outside this author's changes; no fix requested.
- `rg -n 'routeChipTarget|chipTarget\(|headroomProviderID|routeTargetProviderID' AIUsageDashboard/AIUsageDashboardApp/UI AIUsageDashboard/Tests/UITests/RouteSuggestionTests.swift AIUsageDashboard/Tests/UITests/DemoFixtureTests.swift` — exit 0. Both chip callers use routeChipTarget; row continues using routeSuggestion. Visibility filters and the shipped gauge-utilization inputs are preserved.
- `git rev-parse HEAD` / `git status --short`, before and after checks — exit 0, unchanged ad0e55b / clean.
- Brief/result/previous-review/source reads — exit 0. No long-running jobs remain from this review; no server or watcher was started.

## Saved proof and limits

Viewed the author's new `proof/route-ui/fix-r1/overview-usage-tall-dark.png` and `drillin-codex-chip.png`: both retain the Codex chip, agreeing with the row and fixture assertion. No recapture of unchanged site images is needed for this fix. These are saved author captures, not a reviewer app run.

The previous review's UI limits remain: no fresh app-level keyboard disclosure, VoiceOver, actual system Reduce Motion interaction, window/popover resume flow, light/dark capture or real-data route session. This round does not claim to close those live-proof gaps. Full suite, secscan, prove-red and work log remain orchestrator finish gates under the worker rules. No security verdict claimed.

Waits on: orchestrator, for integration and live release gates. No further WP-C fix requested by this review.
