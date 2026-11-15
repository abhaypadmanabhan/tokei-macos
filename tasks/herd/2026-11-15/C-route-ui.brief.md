# Brief WP-C · Route UI and demo data (Claude Opus)

cd /Users/abhayp/wt/lane2 — work ONLY in this directory (branch `patch/2026-11-15/route-ui`, cut from `dev` after WP-B merged).
The single exception: write your result file and proof media at the absolute paths below.

## Read first (in this order)
1. `tasks/patch-bibles/2026-11-15.md`: "Abhay's answers", §0, §3 shared rules, §4 frozen contracts, §5 WP-C
   (your scope and acceptance criteria). That file is the spec; this brief adds logistics.
2. What you build on: `AIUsageDashboard/AIUsageDashboardApp/Core/Utilization/Route*.swift`. `RoutePlan.make(snapshots:now:)`
   returns `generatedAt`, `rows`, `unknown`, `recommendation`. A row has: id, providerID, providerName,
   accountLabel, windowType, windowLabel, remainingPercent, resetAt, secondsToReset, paceState, disposition
   (ready or avoid), reason, validUntil, expiringAt. Unknown has: id, providerID, accountLabel, reason. Do not
   change these types; if the UI needs something, add a view-side helper and say so in the result.
3. Where it shows: `UI/MenuBar/**` (popover, `MaxxerMath.routeTarget`), `UI/Overview/**`, `UI/Dashboard/DashboardProviderPane.swift`
   (`isRouteTarget`), `UI/Components/{PaceCopy,PaceViews}.swift`, `UI/Dashboard/DashboardStatusStrip.swift` (the 1 Hz timer),
   `App/ProofRoute.swift`, `App/WindowVisibilityMonitor.swift`, `Core/Game/BurnSnapshot+Sample.swift` (the sample pattern), `PadzyTheme.swift`.
4. Load skills: `swift-swiftui`, `mac-design`, `mac-verify`. The app keeps its shipped theme tokens; do not
   restyle, and do not load or apply the retired `padzy-os` skill. Sentence case, no eyebrow labels, numbers in
   the app's existing numeric style, one accent per view, Reduce Motion honoured.

## Order of work
1. Demo data first (AC 2), then the website captures of the screens that already exist (AC 3), and send
   `hc send t1d "C captures ready"` as soon as those PNGs are in place; the website lane is waiting on them.
2. Then the route UI (AC 1), the hidden-timer fix (AC 4), proof (AC 5), and a second capture pass that adds the
   popover and Overview with the new route row.

## Rules
- Staff-engineer loop: small commits, tests that fail on the old code where logic changes.
- Build and test: `cd AIUsageDashboard && xcodegen generate`, then `xcodebuild -project AIUsageDashboard.xcodeproj
  -scheme AIUsageDashboardApp -configuration Debug -derivedDataPath ~/Library/Developer/TokeiWork/dd-route-ui build`
  and targeted `-scheme AIUsageDashboardCore … -only-testing:` runs. Then `bash .claude/gates/run-all.sh fast`.
- Launch only your own Debug build from your DerivedData, with proof routes; never launch, quit or alter the
  installed `/Applications/Tokei.app` or its preferences. Quit what you start.
- Captures: own-window PNGs at 2x; with the demo fixture only. Nothing real in any image meant for the site.
  Proof media never goes in git.
- The demo fixture is Debug-only code and must not compile into Release (check with a Release build of the Core
  scheme or a `#if DEBUG` grep, and say which).

## Result
Write `/Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/C-route-ui.result.md`: line 1 `STATUS: READY` or
`STATUS: BLOCKED`; per AC (1-5): what you did, the check, the exact command and output lines, capture paths
(`~/Library/Developer/TokeiWork/proof/route-ui/…`); commits (`git log --oneline dev..HEAD`); known gaps.
When the file is complete and your commits are final, run: `hc send t1d "C-route-ui result written"`
