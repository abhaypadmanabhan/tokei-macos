# Provider connection audit — 2026-07-21

Verified against live machine data (persisted `usage-store.json` + raw sources on
disk) and cross-referenced with github.com/mm7894215/TokenTracker. Store synced
during the audit; all 7 providers refreshed in one pass.

## Per-provider verdict

| Provider | Fetching? | Detail | Action |
|----------|-----------|--------|--------|
| **Cursor** | ✅ live + fresh | today 1.13M tokens, month 27.6M, quota 0.38% used "Pro (active)", from `cursor.com/api/usage-summary` | none — works |
| **Claude Code** | ✅ | tokens local (today 209M, lifetime 2.25B), live quota session 61% / weekly 28% / model 8% via Anthropic OAuth usage | **FIXED** authStatus cosmetic (WP-9) |
| **Codex** | ✅ | tokens local (month 697M), weekly quota 1%, cost ~$553 est. | none |
| **opencode** | ✅ (after fix) | DB read failed intermittently ("unable to open database file") | **FIXED** immutable=1 WAL open (WP-9) — now 165.9M lifetime |
| **Antigravity** | ⚠️ partial | plan (Pro) + 1000 credits shown; weekly/5h quota NOT local | see below |
| **Gemini** | ⚠️ not signed in | `~/.gemini/oauth_creds.json` absent | user: run `gemini`, sign in |
| **Cline** | ⚠️ idle | 0 sessions in 24h → nothing to read (not a failure) | populates on use |

## Antigravity ≈ Gemini (user note confirmed)

Antigravity is Google's agentic IDE running Gemini models; it stores under the
Gemini tree (`~/.gemini/antigravity`, `antigravity-ide`) and opencode even ships an
`opencode-antigravity-auth` module. TokenTracker reads Antigravity via
`~/.gemini/antigravity*/brain/**/transcript.jsonl`.

**Reality on this machine:** those transcripts exist but contain only conversation
steps (`step_index / source / type / status / created_at / content`) — **no token
counts, no usageMetadata**. So:
- **Antigravity token totals are NOT locally available as real counts** — only
  estimable by tokenizing `content` (what TokenTracker's "passive reader" must do).
  That would be an `.estimated` figure, not `.providerReported`.
- **Antigravity weekly/5h quota** lives only in the Antigravity app UI; the local
  IDE endpoint the current `AntigravityQuotaClient` probes ("could not be
  discovered") is the only possible local path and it's not returning windows.
- Signing into the **Gemini CLI** enables Gemini's own quota (separate OAuth) but
  does **not** grant Antigravity weekly quota — different surface, same Google
  backend.

**Recommendation (follow-up issues, not this fix):**
1. Gemini — document the one-time `gemini` sign-in; already an honest empty state.
2. Antigravity tokens — optional `.estimated` token count from `transcript.jsonl`
   content length, clearly badged; low ROI, decide before building.
3. Antigravity quota — reverse-engineer the local IDE quota endpoint (research
   task); until then plan + credits is the honest ceiling.

## Fixed this pass (WP-9, live-verified)

- **opencode** `immutable=1` WAL open → reads 165.9M lifetime tokens, warning gone.
- **Claude** `authStatus` → `.authenticated` when live quota flows.
