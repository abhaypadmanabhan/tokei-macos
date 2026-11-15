VERDICT: CHANGES

S1 [should] AIUsageDashboard/AIUsageDashboardApp/UI/Overview/OverviewViewData.swift:250 Both chips now urge a switch for equal or nearly equal plans, bypassing the shipped human presentation policy. The drill-in has the same change at UI/Dashboard/DashboardProviderPane.swift:100. Two identical 30%-used weekly plans now mark Claude Code “Send here next”; even 83% versus 84% gets that chip. RouteTargetPolicy.human deliberately suppresses these cases. WP-C asks to keep the chip while adding the ranked row; it does not require removing its quieting rule. Fix: retain the row's RoutePlan recommendation, but gate chip visibility using the existing human spread/headroom policy. Whenever shown, the chips must name that same recommendation. Add equal/near-equal chip-visibility cases alongside the single-plan case.

Repro: `python3 -` with the inline Swift probe in command 4 (exit 0) -> `equal: core=claude_code state=recommend chip=claude_code oldHuman=nil`. The one-point-spread and nearly-spent cases show the same change from the old visibility rule. One plan is correctly quiet (`state=onlyOne chip=nil`). This is a presentation regression, not a disagreement about which plan ranks first.

No blocker or other should finding. No source edits, commits, app launches, installed-app copies or quits.

## Commands and actual results

Reviewed HEAD `17027c2c449834e4d54691297b4d0f8885944520` against dev `f5b926de3e447dd16036562d53ca405e3623bb9a` in `/Users/abhayp/wt/lane2`.

1. In AIUsageDashboard: `xcodegen generate` — exit 0. Created AIUsageDashboard.xcodeproj.

2. Covering tests (one invocation), exit 0:

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
  CODE_SIGNING_ALLOWED=NO test \
  > /Users/abhayp/Library/Developer/TokeiWork/review-route-ui-tests.log 2>&1
```

Actual output:

```text
Executed 80 tests, with 0 failures (0 unexpected) in 1.980 (2.003) seconds
** TEST SUCCEEDED **
```

The build emitted concurrency/unused-result warnings in unchanged Core/test files and AppIntents metadata notices. No baseline build was run to classify those warnings.

3. App Release build, exit 0:

```sh
cd /Users/abhayp/wt/lane2/AIUsageDashboard
xcodebuild -project AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardApp -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui \
  CODE_SIGNING_ALLOWED=NO build \
  > /Users/abhayp/Library/Developer/TokeiWork/review-route-ui-release.log 2>&1
```

Actual output: `** BUILD SUCCEEDED **`. Chart deprecation warnings and AppIntents metadata notices appear in the log. No app was launched.

4. S1 synthetic probe against the actual RouteCopy helper and built Core framework, exit 0:

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
for (label, snapshots) in [("one", [sample(.claudeCode, used: 30)]),
    ("equal", [sample(.claudeCode, used: 30), sample(.codex, used: 30)]),
    ("one-point-spread", [sample(.claudeCode, used: 30), sample(.codex, used: 31)]),
    ("nearly-spent", [sample(.claudeCode, used: 83), sample(.codex, used: 84)])] {
    let plan = RoutePlan.make(snapshots: snapshots, now: reference)
    let suggestion = RouteSuggestion.make(plan, snapshots: snapshots, now: reference)
    let human = RouteTargetPolicy.human.routeTarget(in: UtilizationEngine.utilizations(from: snapshots), now: reference)
    print("\(label): core=\(plan.recommendation?.providerID.rawValue ?? "nil") state=\(suggestion.state) chip=\(suggestion.target?.rawValue ?? "nil") oldHuman=\(human?.providerID.rawValue ?? "nil")")
}
'''
folder = '/Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui/Build/Products/Debug'
env = dict(os.environ, DYLD_FRAMEWORK_PATH=folder)
r = subprocess.run(['swift', '-F', folder, '-framework', 'AIUsageDashboardCore', '-'], input=source + probe, env=env, text=True)
raise SystemExit(r.returncode)
PYPROBE
```

```text
one: core=claude_code state=onlyOne chip=nil oldHuman=nil
equal: core=claude_code state=recommend chip=claude_code oldHuman=nil
one-point-spread: core=claude_code state=recommend chip=claude_code oldHuman=nil
nearly-spent: core=claude_code state=recommend chip=claude_code oldHuman=nil
```

5. Release binary inspection, exit 0:

```sh
python3 - <<'PYSTRINGS'
from pathlib import Path
import subprocess
root=Path('/Users/abhayp/Library/Developer/TokeiWork/dd-review-route-ui/Build/Products/Release/Tokei.app/Contents')
files=[root/'MacOS/Tokei', root/'Frameworks/AIUsageDashboardCore.framework/AIUsageDashboardCore']
terms=['DemoFixture','TokeiProofFixture','TokeiDemoRoute','TokeiProofTickReport','TokeiProofRouteExpanded','demo fixture','SecondTicker','RouteSuggestion']
for p in files:
    result=subprocess.run(['strings','-a',str(p)],text=True,capture_output=True)
    print(p.relative_to(root))
    print('strings exit='+str(result.returncode))
    for term in terms:
        print(term+': '+str(sum(term in line for line in result.stdout.splitlines())))
    if result.returncode:
        raise SystemExit(result.returncode)
PYSTRINGS
```

All six demo/proof terms returned 0 in both binaries. App controls: SecondTicker 4, RouteSuggestion 2. This agrees with the #if DEBUG boundaries around the fixture, its app-entry hooks, ProofRoute and BurnDebug. No Release argument, default or environment value can reach fixture code absent from the binary.

6. `bash .claude/gates/run-all.sh fast > /Users/abhayp/Library/Developer/TokeiWork/review-route-ui-gates.log 2>&1` — exit 0, ALL GATES GREEN. Format and lint explicitly SKIP because swiftformat/swiftlint are not installed. The no-secret stage says “empty diff, nothing to scan”: this staged-only run is not a security scan of the committed branch.

7. Static verification:

- `git diff --check dev...HEAD` — exit 0, no output.
- `git status --short` before and after generated project/checks — exit 0, no output (clean).
- `git branch --show-current` — exit 0, patch/2026-11-15/route-ui.
- `git diff --stat dev...HEAD` — exit 0, 21 files, 1090 insertions, 47 deletions.
- `rg -n 'visibleUtilizations' AIUsageDashboard/AIUsageDashboardApp AIUsageDashboard/Tests` — exit 1, no matches, the expected “no callers remain” result.
- Source/brief/result/feature-map reads and relevant diffs completed with exit 0. One initial broad rg included guessed App/DashboardWindow.swift and Core/ViewModels paths and exited 2; corrected discovery found DashboardWindow in App/DashboardNavigator.swift and the view model in Core/Sync.
- `df -h /Users/abhayp/Library/Developer/TokeiWork` — exit 0, 224 GiB available before builds.
- `lsof -nP -iTCP -sTCP:LISTEN` — exit 0; no server/watcher was started by this review. All test/build/probe sessions exited 0.

8. Saved captures:

- `sips -g pixelWidth -g pixelHeight <each required site-capture PNG>` — exit 0. Popover is 640×1402; Overview usage/quota, Burn, Value, Agents and Claude detail are each 2200×1520, consistent with the claimed 2× frames.
- Viewed existing route popover expanded dark/light, Overview route dark, Codex drill-in chip, all four alternate-state popovers, and site Agents/Claude detail/Value/Burn through view_image. Rows render, inspected text is readable, and the material uses fictional data and generic tilde paths. Expanded popover runner-up text fits. These are the author's saved captures, not a fresh reviewer launch.

## Acceptance criteria and focused review coverage

- AC 1: row is in popover and Overview, reads RoutePlan's reason and reveals at most two runners-up for a recommendation. One/none/stale/all-nearly-used-up states have copy and no paid-credit/overage call to action. Row and chip provider targets share the helper; S1 is the extra visibility change. Pure copy tests pass. VoiceOver summary includes plan/window/reason; disclosure is a standard Button with a label. Fresh keyboard and VoiceOver operation remain unproven.
- AC 2: fixture holds only literals/synthetic values. Refresh uses a demo-only registry; usage store, quota series, burn state and snapshot writer are explicitly injected with the demo temp directory. Normal Debug launch does not construct this model without the fixture switch, and Burn's fixed sample does not enter the real sync model. All five fixture tests pass, including string walk and refresh. Release isolation verified above. No fresh app-level file-access trace.
- AC 3: required capture files exist under the named proof root with expected dimensions; representative saved images inspected as above. No reviewer recapture.
- AC 4: SecondTicker creates a timer only when visible, invalidates on hiding/disappearance/deinit, catches up on reappearance and captures self weakly. Three timer tests pass. Dashboard uses its own window's occlusion; drill-in chooses a fresh static label while hidden and a periodic TimelineView when shown. The author's saved tick report records 0 fires while hidden/closed with popover open, then 4/5 fires after return/reopen. Read, not rerun. No retain cycle found by reading. Route calculation walks the small provider/window set in view bodies; not benchmarked and no material cost established.
- AC 5: system Reduce Motion gates the new disclosure animation. Saved light/dark route captures inspected; app intentionally forces shipped dark appearance. The TokeiReduceMotion capture argument is read by BurnDebug, not RouteNextView, so its still image does not demonstrate the new disclosure operating under actual system Reduce Motion.

## Not checked / ownership

No app launch or installed app interaction; fresh countdown/window/popover resume flow; keyboard disclosure activation; VoiceOver; actual Reduce Motion interaction; fresh light/dark screenshots; profiler measurement; or real-data route session. These remain for the orchestrator's app proof. Full suite, secscan, prove-red and work log are orchestrator finish gates under worker rules, not rerun here. No security verdict claimed.

Recommendation: fix S1 with one shared chip-visibility gate and focused equal/near-equal assertions, retain the row, then re-review that slice. Waits on: WP-C author/orchestrator.
