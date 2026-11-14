# WP-A fix round 1 (orchestrator ledger)
Review: A-review-r1.md (Claude Opus, VERDICT: CHANGES).
Fix (smallest change, one focused failing-first test each, as the reviewer suggests):
- S1 blocker: record moments only for a new period beating an earlier period's record; same-period growth silent; streak achievedAt = run's first day; nudge key record|kind|achievedAt (no value). Update the two tests named.
- S2 should: once-per-window nudge key tolerant of reset jitter (reuse PredictiveQuotaWarning.Key + suppresses). Test 1 s and 10 min jitter → one nudge; next real window → one more.
- S3 should: merge samples whose resets are within resetTolerance into one outcome (latest reset wins). Repro as a test → 1 outcome at 95%.
- S4 should: VM passes hiddenProviders to the engine; VM test with a hidden provider's samples.
- S5 nit ACCEPT: request [.alert, .sound]; burn requests stay sound: false.
- S6 nit ACCEPT: notifyBurn runs in its own Task; refresh/applyLive do not await it (no spinner stuck behind a permission prompt).
- S10 nit ACCEPT: skip reassigning `burn` when equal apart from generatedAt.
- S11 nit ACCEPT: timing test asserts < 250 ms, keeps printing the measured value.
Declined: S7 (rare, reading; follow-up), S8 (Maxxer dedupe is outside WP-A scope; orchestrator follow-up), S9 (note for WP-C).
Then rerun your targeted classes once, update A-burn-engine.result.md (add a "Review r1 fixes" section with each id → commit + test), print TOKEI_A_DONE.
