# WP-W round 2b: review r1 fixes (orchestrator ledger)
Review: W-review-r1.md (Codex Sol, VERDICT: CHANGES).
Fix:
- S1 should: copy must not promise overage never scores. Say burn counts usage on your plans; pay-per-token keys
  never count; nudges never point you at paid overage; plus one quiet line for the limit: "Claude's extra usage is
  billed inside the same logs, so Tokei can't separate it yet." (or plainer). Keep §7 honest everywhere on the page.
- S2 should: the copy gate scans normalized text per block across inline descendants (sentence boundaries kept);
  add the reviewer's `<strong>` fixture to the gate tests (it must fail before your fix).
- S3 nit ACCEPT: budget gate fails when a local video/source reference does not exist.
- S4 nit ACCEPT: Reduce Motion toggled mid-visit: keep the film suppressed for the rest of the visit (simplest).
- Dependency hygiene: if nothing imports the `shadcn` package at runtime or build time (check globals.css for
  `@import "shadcn/..."` and every import), remove it from dependencies in its own commit; rerun the audit and say
  whether the last critical (proxy-addr) is gone. If something does import it, leave it and say what.
Then: clean build with every gate, test:gates, headless proof at 1440 + 390 (console errors 0), append a
"Round 2b" section to W-site.result.md (id -> commit + check), keep STATUS: READY if all pass, print TOKEI_W_DONE.
Round 2c (reconcile strings/visuals with the merged app + CLI) still comes later; do not start it.
