# WP-E fix round 1 (review: /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-review-r1.md, read it fully, probes included)

Each with a test that fails on your current code first:
- S1 (blocker): the exported snapshot's `recommendation` still ignores the Codex individual cap, so the route
  row and `get_recommendation` / `tokei status` / `tokei guard` disagree. One `Utilization` initialiser from a
  window (applying `routingWindowType`) used by every call site the review lists; the test asserts the exported
  snapshot's `recommendation.routeTo` and `.avoid` equal the plan's.
- S2 (should): the cap binds, but a provider or account with ONLY the cap and no flat-rate plan window is never
  a row, never counts as covered and is never recommended (that would route work to paid credits). Test: cap
  only → no row, no recommendation.
- S3 (should, accepted now): `get_recommendation` and `tokei status` no longer pass the snapshot's
  `recommendation.reason` or `reasonCode` through raw: gate the sentence through the plain-text check with a
  fixed fallback (or rebuild it) and map `reasonCode` through a fixed allowlist. Output for an untampered
  snapshot stays byte-identical (test), a tampered one gets the fallback (test).
- S4 (nit, accepted): keep combining marks legal (Indic, Arabic, Thai and accented labels must survive) and
  bound the label by unicode scalars or UTF-8 bytes instead, so flooding is still impossible. Tests: a Devanagari
  or Malayalam label survives unchanged; one letter plus 100,000 marks is rejected.
- S5: only if it is a one-line change. S6: declined for now (needs a Release build in the gate); note it as a known gap.
Rerun the touched classes plus the Codex quota, route, MCP, CLI status and sanitiser classes, then the fast gate.
Append "Fix round 1" to your result file, then
`echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/E-fix-r1.done` and run
`hc send t1d "E fix r1 done"`.
