# WP-B fix round 1 (orchestrator ledger)
Review: B-review-r1.md (Claude Opus, VERDICT: CHANGES). Smallest fix each, one failing-first test each.
Fix:
- S1 blocker: pass the user's environment through; never inject CLAUDE_CONFIG_DIR or CODEX_HOME. Test with neither set (child sees neither). Re-prove the temp-HOME live connect for Claude and Codex with both unset (`env -i HOME=$H PATH=...`), and that `claude mcp get tokei` under that HOME finds it.
- S2 should: symlinked ~/.cursor/mcp.json: resolve the link and write the target atomically in the target's directory, back up bytes (not the link), never chmod through a link. Test.
- S3 should: Cursor refuses a different existing `tokei` entry like Claude/Codex ("Disconnect it first"); docs §7 updated. Test.
- S4 should: Claude match requires user scope; uninstall of a local-scope entry says how to remove it (`claude mcp remove tokei -s local`). Stub test.
Accepted nits: S5 (match only the clients' own "no server" phrases), S6 (child PATH = found binary's dir + fallback dirs + inherited PATH), S7 (.withoutEscapingSlashes), S9 (refuse Connect/Install from /AppTranslocation/ or /Volumes/: "Move Tokei to Applications, then retry"), S10 (no PATH hint from Settings), S12 (`tokei mcp` with extra args other than install/uninstall still starts the server, as before), S13 (additive `available:false` when the snapshot has no burn block).
Declined (follow-up): S8, S11, S14, S15.
Then rerun your targeted classes once (the 14 the reviewer ran + any new), update B-agent-surface.result.md with a "Review r1 fixes" section (id -> commit + test), keep line 1 STATUS as READY except AC7 GUI proof which the orchestrator owns (write READY), print TOKEI_B_DONE.
