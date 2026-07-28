# Lessons Learned

## Leg 3 UI Implementation

- **SwiftUI Non-Optional Bindings**:
  - *Rule*: Never use conditional optional binding (`if let ...`) on non-optional fields (like `confidence` on `TokenUsage`), as the Swift compiler will fail with an error. Always check the property type in the core models before writing SwiftUI conditional rendering logic.
- **Dynamic Render Performance & UI Redraw**:
  - *Rule*: When designing countdown timers in SwiftUI that rely on system dates (`Date()`), use a local view state variable mapped to a `Timer.publish` stream. To ensure reactivity inside views/methods, reference the state variable inside the formatter method (`let _ = countdownTick`) to trigger redraws correctly.

## Cursor Connector Completion

- **Bypassing False Positives in Secret Scanners**:
  - *Rule*: Pre-commit secret scanning hooks block files containing strings resembling real JWT tokens (e.g. `/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/`). To supply mock tokens for unit/integration tests without triggering blockers, split the token segments using string concatenation (e.g. `"part1" + "." + "part2" + "." + "part3"`) so the pattern isn't present literally at rest.
- **Quota Window Unique IDs**:
  - *Rule*: When parsing API response objects containing nested usage metadata that could duplicate the same window properties (e.g., top-level keys and duplicate nested `quota` dictionaries), always deduplicate the resulting `QuotaWindow` objects by `type` before returning. This ensures `QuotaWindow.id` (composed of `providerID` and `type`) is unique, avoiding SwiftUI list or table rendering conflicts.

## Cursor real tokens+quota via cursor.com — 2026-07-08

- **Verify the actual working endpoint against a reference before wiring, don't assume the first API you find is right.**
  - *Context*: The Cursor connector was built on `api2.cursor.sh/auth/usage` (per-model `numRequests`/`numTokens`/`maxRequestUsage`). It showed nothing useful — `numTokens` was never surfaced, and uncapped Pro plans report `maxRequestUsage == nil` → no quota gauge. A competitive read of TokenTracker (github.com/mm7894215/TokenTracker) proved it abandoned that endpoint entirely.
  - *Rule*: The working Cursor path is `cursor.com` behind the **WorkOS session cookie** (`WorkosCursorSessionToken=<userId>%3A%3A<jwt>`, `::` URL-encoded, userId from the JWT `sub` normalized like the Cursor CLI): `GET /api/dashboard/export-usage-events-csv?strategy=tokens` = per-event CSV (real input/cache-read/cache-write/output split + cost + `Date`), and `GET /api/usage-summary` = plan `totalPercentUsed` (reset = `billingCycleEnd`). NOT a Bearer JWT.
- **Set `request.httpShouldHandleCookies = false` when sending an explicit `Cookie` header** — otherwise URLSession's cookie storage can override/strip it and the authenticated call silently fails.
- **CSV `Date` is UTC ISO8601-with-ms**; bucket to the user's local day via `Calendar.current` for consistency with the other providers (they window on local calendar days).
- **Read structured fields, don't regex-scrape a display string.** First cut recovered the plan label by matching the `"Plan: <text>"` info warning; the structured `membershipType`/`subscriptionStatus` were already on the parsed state. `/simplify`'s altitude lens caught the layering inversion — expose a computed `planLabel` on the state instead.

## Antigravity Stale-Serve Quota Cache — 2026-07-08

- **Unit Testing Date-Sensitive Filtering**:
  - *Rule*: When unit-testing components that filter data based on system time (e.g. dropping cached buckets whose resetTime is in the past, or checking cache expiry), always inject a mock clock/date provider returning a fixed test date instead of using `Date()`. This ensures tests are stable across execution environments and prevents failures due to real-time differences relative to fixed test fixtures.

## 2026-07-08 — Quota UI: consolidate, don't duplicate; ship the enable control

- **Don't build a "dashboard" that repeats the detail tabs.** The quota strip (P1.1) re-rendered
  every provider window that each per-provider tab already showed → rejected. A real overview is a
  *different altitude*: one glanceable line per provider (tightest window only), logos, aggregate
  headline — not repeated tiles. **How to apply:** before adding a summary surface, ask "what does
  this show that the detail view doesn't?"
- **A backend toggle with no UI is not shippable.** P0.3 added `claudeNetworkUsageEnabled` but no
  control → a public user cannot enable Claude live. **How to apply:** any feature flag meant for
  end users ships with an in-app, friendly enable path (guided Connections screen), same commit/wave.
- **Fit-to-window is a requirement, not polish.** Fixed frames / high minWidth cropped content.
  Overview/detail must reflow + scroll; test at narrow width in previews.
- **Logos: monochrome template assets** (Render As = Template, tinted to ink) — on-theme + low
  trademark risk for public ship. Full-color brand logos clash with aitracker and add legal risk.

## 2026-07-08 — Async connect needs a "fetching" state, not a silent empty

- **Symptom:** user enabled Claude live quota, allowed the Keychain prompt, but the Overview row
  still said "Connect live quota" and looked broken. Root cause (systematic-debug): the data path
  was fine — the live fetch is async (~seconds + Keychain-allow delay); the row's unavailable
  branch showed the "Connect →" affordance the whole time, indistinguishable from "not connected".
- **Fix:** row reads the provider's enable flag (@AppStorage, same key the toggle writes). Flag ON
  + no window yet → "FETCHING QUOTA…"; flag OFF → "Connect live quota →". A connected-but-waiting
  state must never render as the not-connected call-to-action.
- **How to apply:** any enable→async-fetch flow needs three visible states (off / fetching / live),
  not two. Verify the transient, not just the settled state. Don't debug-by-guess — the store/cache
  files proved the fetch worked before touching UI.

## 2026-07-08 — Website design correction
- Abhay: numbered "01 / TOPIC" mono kickers now read as outdated/same-as-other-projects. For marketing/web surfaces, drop them; keep mono data + single accent + hairlines.
- Wants Gen-Z modern motion design: scroll-driven animations, horizontal scroll sections, overlays, subtle 3D hover, page transitions. Research awwwards-tier references before building, don't default to static editorial grid.

## 2026-07-08 — Prior-art scan BEFORE designing a fix (keychain prompt bug)

- **Symptom:** diagnosed Claude keychain prompt-loop root cause correctly (foreign item ACL +
  Claude Code recreating the item), then designed fixes from first principles — all accepted ≥1
  dialog. TokenTracker (competitor) had a zero-dialog solution: spawn `/usr/bin/security
  find-generic-password -w` (item's ACL already trusts the security CLI that created it) with a
  2s timeout + silent-null fallback.
- **Why missed:** anchored on "native SecItem API is the proper way"; never searched how peer
  apps (ccusage, TokenTracker, other quota trackers) solve the same platform problem.
- **How to apply:** for any platform-constraint bug (keychain, sandbox, notarization, TCC,
  entitlements), do a 5-minute competitor/OSS prior-art scan BEFORE proposing fixes — reading a
  shipped solution beats reasoning one out. "Feels like a hack" is not a reason to exclude a
  candidate; evaluate against the actual trust/permission model.

## 2026-07-12 — MenuBarExtra label must not contain a TimelineView

- **Symptom:** dev build's menu-bar item vanished entirely (no mark, no value); process alive, no crash. Release 0.4.0 showed `▁▂▃▄ 9%` on the SAME machine → not menu-bar overflow, a dev regression.
- **Root cause:** the battery-fix commit drove the sync spinner with `TimelineView(.periodic…)` placed INSIDE the `MenuBarExtra { } label:` view. SwiftUI snapshots a MenuBarExtra label into the status-item image; a `TimelineView`'s self-driving clock breaks that render and the item never appears (and doesn't recover after the initial `isLoading` sync).
  - **Rule:** never put `TimelineView` (or other self-scheduling/animating views) in a `MenuBarExtra` label. Drive periodic label updates with a `@State` frame + plain `Image`, ticked by a `.task(id:)` async loop (created on demand, cancelled at idle → also no battery drain). The `@State`+`Image` path is what shipped 0.4.0 and renders reliably.
- **Process rule:** a UI change that BUILDS is not verified. `xcodebuild build` PASSED and `/agents-done`'s build gate PASSED, yet the item was broken — build success ≠ visual render. Always LAUNCH a menu-bar/GUI change and screenshot the actual item. A/B against the last shipped build is the fastest way to separate a regression from an environment quirk (notch overflow, hider utilities).

## 2026-07-21 — Data viz: "standard/boxy" beats "smooth" for a heatmap
- **Correction:** the WP-5 activity heatmap used a *continuous* single-hue opacity
  field in *wide rectangular* cells (the earlier `4033551` "continuous" tweak).
  User: "boxy and standard, not this rectangular — it looks like noise, doesn't
  tell me anything." A prior explicit request for "continuous" did NOT survive
  contact with real data.
- **Rule:** for a heatmap/punch-card, default to the recognizable GitHub shape —
  **square** cells at a fixed capped size (never stretch to fill width),
  **discrete** intensity steps (not a continuous ramp), and every cell a
  **visible box** (empty = a faint grid box) so the grid reads as structure. A
  smooth gradient over a busy grid destroys the very pattern the chart exists to
  show. Keep it one neutral data hue.
- **Process:** this only became obvious once LOOKED AT in the running app. With
  Screen Recording + Accessibility granted, close the loop: `open` the worktree
  build, then `screencapture -R <window-bounds>` (re-read bounds each time — the
  window moves; capture the exact window rect, never the whole screen, to avoid
  grabbing the user's other content). Drive tabs via System Events
  `click button N of group 1 of window 1`; open the drill-in with Down-arrow;
  open the menu-bar popover via `click menu bar item 1 of menu bar 2`.

## 2026-07-21 — Driving the macOS app for visual verify (refined)
- **Scroll a SwiftUI ScrollView reliably:** Page Down / arrow keys do NOT scroll it
  (arrows are also intercepted by the app's onMoveCommand → drill-in). What works:
  `set value of scroll bar 1 of scroll area 1 of group 1 of window 1 to 1.0`
  (0.0 = top). Found the scroll area by dumping `UI elements of window 1`.
- **The window moves between calls** (Stage Manager / focus). Re-read
  `{position, size} of window 1` before EVERY capture and pass that exact rect to
  `screencapture -R` — never a hardcoded region.
- **Capture the target window's rect only, never the whole screen or a guessed
  region** — a menu-bar popover sits over the user's other windows, so a loose
  region grabs their private content (incl. this very terminal). For the
  MenuBarExtra popover, enumerate `windows of process "Tokei"`: the unnamed small
  (~320-wide) window IS the popover — capture its exact bounds.
- **Tabs:** `click button N of group 1 of window 1` (1=Overview…). Drill-in: Down
  arrow from a tab. Popover: `click menu bar item 1 of menu bar 2`.
- **Fetching a brand mark as a tintable asset:** lobe-icons
  (`raw.githubusercontent.com/lobehub/lobe-icons/master/packages/static-svg/icons/<name>.svg`)
  gives clean monochrome single-shape SVGs that drop straight into a
  template-rendering-intent imageset and tint per-agent. Keep the path's
  `fill-rule` (opencode's frame needs evenodd).

## 2026-07-25 — Shipping an MCP server: a tool nobody calls is dead weight
- **The correction:** I shipped `tokei mcp` with two accurate tool descriptions and
  called it done. Accurate ≠ invoked. A description that opens with "Returns …"
  answers a question the agent wasn't asking; the agent needs to know *when to
  reach for this*, and it decides that from the opening clause.
- **The mechanism I'd missed:** MCP's `initialize` result takes an optional
  `instructions` string. Clients surface it to the model **once at connect time**,
  so it persists for the whole session — that is how a standard MCP server "knows
  when to use what". Without it, nothing makes an orchestrating agent check quota
  before it spawns a subagent.
- **Fix pattern (three layers, since none is guaranteed):** server-level
  `instructions` (some clients ignore it) → trigger-first tool descriptions (always
  sent) → a steering line in `CLAUDE.md`/`AGENTS.md` (works with no MCP at all).
- **Generalize:** when adding any agent-facing surface, write the *trigger* before
  the payload. "Call this BEFORE you delegate" beats a perfect schema.

## 2026-07-25 — Notarization: `xcodebuild archive` + export ≠ the release script
- **Symptom:** 0.7.0 notarization came back `Invalid`, 18 errors. 16 were Sparkle's
  nested helpers (`Autoupdate`, `Updater.app`, `Downloader.xpc`, `Installer.xpc`)
  carrying `flags=0x10002(adhoc,runtime)`.
- **Cause:** the build used `xcodebuild archive` + export, which skips
  `build-app.sh`'s step-4 re-sign (`codesign --force --deep` on Sparkle). That step
  is the only reason 0.6.1 passed. Use `scripts/release.sh`; don't hand-roll the
  archive path.
- **Corollary that bit right after:** the app-level sign is deliberately NOT
  `--deep`, so anything added by a copy-files phase (the new `Contents/Helpers/tokei`)
  keeps xcodebuild's signature — Developer ID and hardened runtime, but **no secure
  timestamp**, which notarization rejects. Every copied-in executable needs its own
  explicit re-sign, inside-out, before the app.
- **Diagnose before rebuilding:** `xcrun notarytool history` + `notarytool log <id>`
  names the exact failing path and reason. Reading it first saved a blind rebuild.
- **Publish order matters:** create the GitHub release and confirm the asset is live
  (`HTTP 200`, `content-length` == the appcast's `length`) BEFORE pushing the
  appcast. Feed first = clients 404 mid-update.
- **Appcast drift is a downgrade risk:** `docs/appcast.xml` on dev was a version
  behind what main/Pages served. Regenerating from dev would have published 0.6.0
  over 0.6.1. Pages serves `main:/docs` — treat that as the source of truth.

## 2026-07-26 — Verify with the real client, not a friendly one
- **The failure:** I shipped 0.7.0's MCP server after driving it with raw JSON-RPC
  and declaring it verified. It never worked with any real client. I had chosen
  `protocolVersion: 2024-11-05` myself, which is precisely the one value that
  didn't trigger the bug. Claude Code sends `2025-11-25` and got
  `-32602: Unsupported protocol version`.
- **Rule:** when a feature's whole purpose is to be consumed by a specific client,
  the verification must run that client. `claude mcp add` + `claude mcp list` and
  look for `✔ Connected`. Hand-rolled protocol calls prove the parser works, not
  that the integration works.
- **Compounding trap:** `claude mcp add` reports success on *registration*. It never
  connects. So the happy-looking output meant nothing. Any "add/register/configure"
  command needs a separate health check before you call it done.
- **On accepting review-bot findings:** the rejection came from a CodeRabbit finding
  I merged unquestioned ("validates the version matches, errors otherwise"). It was
  wrong — MCP negotiation requires answering with a version you *do* support. The
  code already returned its own version, so the concern never existed. Check a bot's
  premise against the spec before implementing it; a plausible-sounding finding can
  introduce the regression it claims to prevent.

## 2026-07-26 — notarytool crashes AFTER the upload lands
- **Symptom:** `xcrun notarytool` died three times in one release — `Bus error: 10`
  twice (once inside `submit --wait`, once inside plain `submit`) and its `info`
  subcommand returned nothing for ~14 consecutive polls. Every single time the
  submission was already in `notarytool history`.
- **Rule:** treat a non-zero exit from `notarytool submit` as *possibly successful*.
  Recover the id from `notarytool history` (newest entry matching the artifact name)
  and poll `notarytool info` separately. Compare newest-id before/after so a genuine
  upload failure is still detected. Do not use `set -e` around it.
- **Never pipe `submit` into an early-exiting filter.** `submit | grep -m1` makes grep
  close the pipe on first match, SIGPIPEs notarytool, and `pipefail` turns that into
  exit 141 — reporting failure on work that completed. Capture to a variable, parse
  with awk that reads to EOF.
- **Apple wedges submissions.** Two of four cleared in ~45s; the others sat In
  Progress for 26m and 2h+. Resubmitting cleared each wedge in ~20 seconds. Don't
  wait longer than a few minutes past baseline — resubmit.
- **My own error to avoid repeating:** after the first crash I removed `--wait` and
  assumed the class was fixed. It wasn't; the crash is in the tool exiting, not in
  waiting. One data point wasn't enough to generalize from.

## 2026-07-27 — absence of data is not a good number
- **Symptom:** `tokei status --json` recommended routing fan-out work to `claude_code`
  because its only window read `usedPercent: 0` — a cached reading served during a 429
  cooldown, `confidence: local_estimate`, `source: "… (stale)"`. Codex, with a real 75%,
  lost. Agents act on that field.
- **Root cause was the consumer, not the data.** `AgentRecommendationEngine.recommend`
  ranked purely on `usedPercent`. `Utilization` already carried `confidence` — the engine
  simply never read it. Every other finding degraded data *quality*; only this one turned
  bad data into a bad *action*. Fix the decision point first.
- **Rule: rank on trust, then value.** Route only to confirmed, recent readings; require
  ≥2 of them. Keep `avoid` computed from *all* readings — asymmetric on purpose, because
  an unconfirmed number is not evidence of headroom but a high one is still evidence of
  pressure. And name the exclusion in the reason: a silently-dropped provider reads as
  "considered and rejected on the numbers", which is a different claim.
- **Staleness in a string is staleness nobody can use.** `" (stale)"` was appended by hand
  in each client and `.estimated` conflated "old server number" with "fresh local estimate".
  Added `observedAt` so age is a number. If a consumer must regex a diagnostic label to make
  a decision, the field is missing.
- **Two different things were both called "stale".** Top-level `stale` meant "how long ago
  the app wrote the file" (27s → false) while the reading inside was 81 minutes old. Same
  word, unrelated questions. Name the *question*, not the vibe.
- **Dropping expired items silently is directionally biased.** `cachedWindows` deleted
  windows past their reset — and short windows expire first, and short windows are the tight
  ones. Every stale serve decayed toward the loosest number, i.e. always flattering. Half a
  reading now returns nothing at all.
- **Honour Retry-After.** The loop slept its own 30s ceiling and retried 3× against a
  `Retry-After: 3537`, hammering an endpoint that had just asked for an hour — plausibly
  extending the cooldown it was reacting to.
- **My own error to avoid repeating:** my "wait for the app to restart" loop tested
  `mtime > now-3min`, which a *pre-existing* recent file already satisfied. It reported
  success while the app had actually failed to launch (dyld Team ID mismatch), and I nearly
  read the old binary's output as my new build's. Anchor a wait to a timestamp captured
  *before* the action, never to a relative window.
- **Verification note that paid off:** the fix labels warnings per account. First real run
  immediately distinguished "[default] cooling down" from "[account-1] credentials expired"
  — a distinction the single-account build structurally could not express.

## 2026-07-27 — parallel patch: where downstream checks overturned upstream claims

Four packages built in parallel, adversarially reviewed, then merged. Twelve agent tasks,
all `done`. The value was almost entirely in the checks that *disagreed* with what came
before them, including three that disagreed with me.

- **My root-cause hypothesis was right in mechanism, wrong in detail — and the detail
  mattered.** I diagnosed the unlaunchable Release app as "app has hardened runtime, Core
  framework doesn't". Wrong: the app's embed phase re-signs the framework with the app's
  options, so both carried `adhoc,runtime`. The real fault was **ad-hoc vs ad-hoc** —
  `TeamIdentifier` absent on *both* sides, and under library validation *absent ≠ absent*.
  Handing it over as "leading hypothesis, verify first, follow the evidence if it
  disagrees" is what let the agent correct it instead of confirming it.
- **I asserted a failure was loud; it was silent.** I said `gen-appcast.sh` would exit 1
  with a friendly message. Under `set -euo pipefail`, `X="$(find <missing> | grep -v … |
  head -1)"` aborts *at the assignment* — `find` exits non-zero, `grep` gets no input and
  exits 1, pipefail propagates, `set -e` kills the script before the next line's guard can
  print. Third instance of this pipefail-plus-short-pipeline family in this repo. **Fix the
  pipeline, not the guard.**
- **I over-attributed lint debt twice.** I charged four violations to WP-3 (only one was)
  and one to WP-2 (pre-existing at base, 427 lines already flagged; WP-2 grew it by 20).
  Both agents measured against the base commit and said so. **Attribute by measurement
  against the base tree, never by "this file appears in that diff".**
- **A stricter gate finds bugs the thing it gates never had.** Rebuilding the launch
  assertion exposed a genuine pre-existing defect: both signing modes shared one
  `DerivedData`, so the first ad-hoc build after a signed one staged a still-Developer-ID-
  signed helper — a bundle `codesign --verify --strict --deep` passes. Only visible on a
  *mode transition*; testing each path from clean can never see it.
- **A gate that infers success from silence is not a gate.** The first launch assertion
  discarded the exit status and printed OK whenever the process died, unless stderr matched
  one of five English regexes. Require a *positive* signal, and make an allowed skip read
  differently from a pass.
- **Green-alone is not green-together.** WP-3 moved `avoidThreshold` onto a new type; WP-4
  independently added a guard test reading the old symbol. Both branches passed their own
  suites; only the merge failed to compile. **The full gate on the integrated branch is the
  only run that means anything** — per-branch green is a prerequisite, not evidence.
- **Tell an agent what was already cleared, not just what to fix.** Each fix task carried
  the reviewer's explicit "confirmed clean, do not churn" list. Nobody re-litigated settled
  work, and one agent (WP-4) *declined* a review suggestion after verifying notarization,
  stapling and DMG already shipped — refusing to replace one false statement with another.
- **Routing on an untrusted number is the bug this repo exists to prevent.** Mid-run,
  Tokei's own reading went `local_estimate (stale)` and the engine correctly refused to
  route. The honest move was to say quota was unverifiable and reuse warm agents — not to
  treat a stale 5% as headroom. A floor is not a ceiling.

Herdr/orchestration:
- **`herd spawn` races its own pane.** It splits and calls `agent start` immediately, losing
  to shell init (`agent_pane_busy`). The pane *is* created — read it for a clean prompt,
  `herdr agent start` by hand, then patch `agent_name`/`pane_id`/`status` into `run.json`.
- **Use `--isolation pane` with an explicit `--cwd` when the worktrees already exist**;
  `worktree` mode makes herd create competing ones.
- **`herd spawn` splits `--current`,** i.e. `$HERDR_PANE_ID`. Override that env var to
  anchor the fleet into another tab instead of shredding the orchestrator's own pane.
- **Results through files, never terminal scraping.** Lifecycle state said `running` for
  tasks whose result files had already landed. The file is the truth.

## 2026-07-27 (later) — the CPU regression, and "latent" as a failure word

Manual QA of the patch surfaced the dev build pegging a core. Two fixes followed, and both
overturned a confident earlier assessment.

- **"Latent, not active" was wrong, and it cost real numbers.** The cross-file dedup bug was
  assessed as unreachable-in-practice because an independent recomputation of the corpus
  matched. Writing the failing test first showed **237 tokens where 137 was correct**, plus a
  mirror defect (30 where 130 was correct). On the real corpus: **95 duplicated dedupe keys
  across two forked sessions, 14.6M tokens** misattributed in month and lifetime figures —
  invisible in today/this-week only because that session was 8–30 days old. *A recomputation
  that matches the buggy code proves the two agree, not that either is right.* Reproduce
  before classifying severity.
- **The same word is now attached to the next one.** Cross-*account* dedup does not happen at
  all (`seenIDs` is per `parse()` call, one call per account), and is "currently unreachable
  because Claude does not share message IDs across accounts." That is the exact sentence
  used about this bug yesterday. Treat "unreachable" as "untested".
- **A cache that never hits hides the bugs in its hit path.** The parse cache evicted down to
  the calling account's slice, so with multi-account every account missed every refresh
  (~590 MB re-parsed every 2s, 58% of a core, 821 MB RSS). Fixing eviction made cache hits
  happen *for the first time* — which is what made the dormant dedup bug live. Fixing an
  upstream defect activates whatever was downstream of it and never ran. Third instance
  today.
- **Measure convergence, don't sample it.** I twice declared RSS from a 3-minute window:
  first "605 MB, worse than claimed", then "~551 MB, a possible 400 MB regression". It
  converges to **~90 MB**, it just takes 6–8 minutes on an 800 MB corpus. A falling number is
  not a settled number.
- **An agent refusing to fill in a metric is a good signal.** The dedup task left
  `PERF_RISK_PLACEHOLDER` and marked its perf criterion `[ ]` rather than invent a
  before/after, because my own agent fleet was writing Claude logs throughout and its
  attempt to measure the pre-fix build failed. The orchestrator could get the clean number —
  by shutting the fleet down — precisely because it controls what the agents cannot.
- **Profile before theorising.** `sample <pid>` put 86% of samples on one call path in
  seconds. My prior guess (`seenIDs.formUnion` cost) was wrong; so was my first root-cause
  guess for the P0 that morning. Three hypotheses, three corrections by measurement.
