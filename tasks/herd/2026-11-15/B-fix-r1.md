# WP-B fix round 1 (review: /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/B-review-r1.md, read it fully, probes included)

Fix, each with a test that fails on your current code first:
- S1 (blocker): the "room relative to pace" key mixes units when a window has no pace (Cursor monthly). One
  comparable score for both cases; a nearly used-up plan must never outrank an empty one. The shipped
  `get_route_recommendation` answer must not get worse than `dev` for the reviewer's P1 case.
- S2 (should): expiring capacity only counts when the account's other limits leave room to spend it. Bound the
  expiring headroom by the tightest other window; below a small floor it is not "expiring unused capacity".
- S3 (should): one rule owns eligibility for both tools, per-model windows included, so `get_route` and
  `RouteTargetPolicy.agent` can never say "send" and "avoid" for the same plan. Extend the AC 1 table to compare
  them when the policy names no target too.
- S4 (should): restore the existing MCP instructions exactly as on `dev` and ADD one paragraph (under 400
  characters) for get_route. Nothing that shipped is deleted.
- S9 (nit, accepted, same class as S3): both callers rank over the same filtered window list.
- S5 (nit, accepted): `for` an agent with no flat-rate plan says so instead of "refresh Tokei".
- S6 (nit, accepted): the Release build path sets `TOKEI_CLI_BINARY` so the built-binary check really runs
  (`scripts/release.sh` or `verify-app.sh`; smallest place).
Declined: S7 (keep the precondition; the gate guards it), S8 (matches the spec and the burn tool).

Rerun the touched test classes plus the existing MCP, CLI, route policy and snapshot classes, then the fast gate.
Append a "Fix round 1" section to your result file (per finding: commit, test, red-then-green lines), then
`echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/B-fix-r1.done` and run
`hc send t1d "B fix r1 done"`.
