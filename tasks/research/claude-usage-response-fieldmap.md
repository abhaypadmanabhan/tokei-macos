# Claude `GET api.anthropic.com/api/oauth/usage` — pinned field map (P0.1)

- **Captured:** 2026-07-08, HTTP 200, this Mac, Keychain `"Claude Code-credentials"` token.
- **Headers:** `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`.
- **Fixture:** `claude-usage-response.json` (pretty-printed real body). **No PII** — contains only
  percentages, reset timestamps, credit figures, and internal model codenames. No email/org/account id was returned.
- **Percent convention for `[QuotaWindow]`:** `used` = `utilization`/`percent`, `limit` = 100,
  `remaining` = 100 − used, `resetAt` = `resets_at`.

## Authoritative source = `limits[]` array
Each entry is one window. Decode THIS (top-level `five_hour`/`seven_day` mirror it but the scoped
weeklies are only fully described in `limits[]`):

| field | meaning | example |
|-------|---------|---------|
| `kind` | window id | `session`, `weekly_all`, `weekly_scoped` |
| `group` | bucket | `session` → `.session`; `weekly` → `.weekly` |
| `percent` | used % (0–100) | `8`, `62`, `49` |
| `severity` | `normal`/… | `normal` |
| `resets_at` | ISO8601 reset | `2026-07-13T02:00:00.47+00:00` |
| `scope.model.display_name` | **generic label for `.perModel`** | `"Fable"` (do NOT hardcode Opus/Sonnet) |
| `is_active` | window currently binding | `true`/`false` |

## Top-level convenience fields (present, use as fallback / cross-check)
- `five_hour` → `.session` : `{utilization, resets_at}`. Here 8.0%, resets 2026-07-09T01:00Z.
- `seven_day` → `.weekly` : `{utilization, resets_at}`. Here 62.0%, resets 2026-07-13T02:00Z.
- `seven_day_opus` / `seven_day_sonnet` / `seven_day_cowork` / `seven_day_oauth_apps` /
  `seven_day_omelette` + codenamed (`tangelo`, `iguana_necktie`, `nimbus_quill`, `cinder_cove`,
  `amber_ladder`) → scoped weeklies, **null when unused**. Prefer `limits[]` scoped rows for labels.

## Extra usage / credits
- `extra_usage` : `{is_enabled:false, monthly_limit:5000, used_credits:2152.0, utilization:43.04,
  currency:"USD", disabled_reason:"out_of_credits"}`. **Hide the window until `utilization` non-zero / enabled** (P0.3 guardrail).
- `spend` : mirrors credits in minor units (`amount_minor`, `exponent`), `percent:43`, `enabled:false`.

## Decoder notes for P0.2
- Reset key is `resets_at` (not `reset_at`). Utilization key is `utilization` (top-level) / `percent` (in `limits[]`).
- Map scoped weeklies **generically** by `scope.model.display_name`; never assume model names.
- `member_dashboard_available:false` present — ignore for quota.
