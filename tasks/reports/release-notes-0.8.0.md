## Tokei 0.8.0

**Tokei can see all your Claude accounts, and it stopped sending work to numbers it
couldn't confirm.** If you run more than one Claude Code login on this Mac, 0.7.x was
reporting one of them as the whole picture.

### Added

- **Every Claude account, not just `~/.claude`.** Tokei reads each Claude config
  directory on the machine and groups them by the **Anthropic identity** the directory is
  signed into. One identity signed in from two directories is one account with one shared
  quota — not two rows and two gauges. Two identities that took turns inside a single
  directory are not merged into one.
- **Per-account usage over time.** One line per account on a shared scale, so "who is
  spending more" is answerable at a glance, with each account's own tokens, share, and
  quota underneath.
- **The card now says which numbers are which.** Token counts add up every account; the
  gauge and quota windows belong to the single account with the most headroom, because
  that is where work can actually be sent. A card reading 50% next to an account at 88%
  was not a bug, but nothing on screen said so. Now it does — by name.
- **Agents get the accounts too.** `get_usage` (MCP) and `tokei status --json` carry one
  row per account: the path to export as `CLAUDE_CONFIG_DIR`, the label, that account's
  tokens, and its own quota windows with when each was observed. Additive — existing
  readers are unaffected, `schemaVersion` stays 1.

### Fixed

- **Work was being routed to quota readings Tokei could not confirm.** A stale or
  locally-estimated 0% could outrank a confirmed 75% and win the routing recommendation.
  Routing now requires trusted readings and names the exclusion in its reason. An
  untrusted provider is still listed under `avoid` when it is at or over the line —
  "don't send work here" needs less certainty than "send work here".
- **One core pegged and ~800 MB re-parsed every two seconds.** With more than one Claude
  account, the parse cache threw away the other accounts' entries on every refresh, so
  nothing ever hit the cache. Measured after the fix on a real 668 MB corpus: every file
  served from cache, zero bytes re-read, the app settling at ~90 MB and effectively 0% of
  a core when idle.
- **14.6 million tokens counted in the wrong place.** Two forked sessions sharing message
  IDs made a cached per-file total get added twice. Month and lifetime figures were wrong
  wherever that overlap existed.
- **Stale quota can no longer masquerade as current.** Every window carries when it was
  observed, a partially-expired cache reports nothing rather than the loosest window it
  still holds, the stale ceiling dropped from 7 days to 2 hours, and a reading dated in
  the future is treated as suspect instead of infinitely fresh.
- **Cursor stopped retrying into a wall.** A `Retry-After` longer than the retry ceiling
  ends the attempt instead of sleeping through repeated retries, and rate-limit and auth
  failures are logged (status codes and intervals only) where the fetch path used to log
  nothing at all.
- **The signed build launches.** Hardened runtime was being combined with ad-hoc signing —
  which passes `codesign --verify` and then fails at load with mismatched Team IDs. The
  build now verifies that a staged `Tokei.app` actually launches and stays running.
- **A Claude account whose log directory was missing reported "not installed"** while its
  usage was being read correctly, and a merged identity now reads live quota from
  whichever of its directories holds usable credentials.

### Known issues

- **Cross-account dedup does not happen.** Deduplication is per parse call, and each
  account is parsed separately. Claude does not appear to share message IDs across
  accounts, so this is currently unreachable — but that is the same sentence that was
  written about the bug above the day before it turned out to be live, so treat it as
  untested rather than safe.
- **Sync starts when a Tokei surface appears.** With the dashboard window closed and the
  menu bar item never opened, the app does not refresh, so the snapshot the CLI and MCP
  server read goes stale. Open the menu once after launch.
- **SwiftLint reports 361 violations under `--strict`** (`main` carries 370). Long-standing
  repo-wide debt, mostly in test files. No error-level violations remain in the surfaces
  this release touched.

### Verification

- Gates: preflight, no-secret, no-large-artifact, no-uncommitted, cli-version-sync, build,
  test — green. `format` is a SKIP (swiftformat not installed) that `STRICT_GATES=1`
  converts to a failure; `lint` is red at the pre-existing repo baseline described above.
- CPU/memory measured on the real corpus with the FSEvents watcher driven by a live Claude
  session: cold parse ~100% of one core for ~2 minutes, then 0.0–0.2% idle at 90 MB RSS,
  3.6–8.0% at ~200 MB under continuous log writes. The pre-fix build reproduces the
  regression at a sustained 100% and 810 MB for comparison.
- MCP verified end-to-end against the real client: `claude mcp list` reports
  `tokei … ✔ Connected`; `get_usage` returned fresh data (`ageSeconds: 1`, `stale: false`)
  with per-account rows; routing correctly excluded Claude while its readings were stale.
- Security review of `main...dev`: one candidate finding (attacker-planted `~/.claude-*`
  directory name reaching the agent snapshot and the `export CLAUDE_CONFIG_DIR=…` clause)
  was raised and **refuted on verification** — the precondition is write access to `$HOME`,
  which already permits writing the snapshot file directly, so the path grants nothing the
  attacker lacks and crosses no privilege boundary. Nothing in Tokei executes the string.
  Recorded as accepted risk with a cheap hardening option: reject control characters and
  shell metacharacters in discovered directory names.

### Rollback

Per work package, newest first — all fast-forwarded onto `dev`, so revert commits rather
than a merge:

```bash
git revert f0c9811 dbd7a42 4d3418d     # multi-account notice
git revert 5ea951e 26dfbee             # per-account graphs
git revert e8906c0 762049e             # identity-keyed accounts
```

Reverting the identity change alone is not safe — the later packages read fields it
introduced. Revert the stack top-down or not at all. If `dev` has already been merged to
`main`, `git revert -m 1 <merge-sha>` backs out the whole release; `main` @ `8bb8768` is
the shipping 0.7.1 line.

### Manual QA

Functional, CLI and MCP paths verified live against the real corpus and the real Claude
Code client (see Verification). The SwiftUI surfaces were exercised by running the dev
build with the dashboard open — not by a full click-through of every state, and the
multi-account UI in particular has been seen with two accounts, not with an unreadable
directory or a three-account layout.
