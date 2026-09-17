# Herd budget account-aware consumer specification

This is a copy-paste implementation handoff for the Herdr-owned files. This Tokei
work package does **not** edit `$HERD_VAULT/bin/herd-budget` or
`$HERD_VAULT/bin/herd-roster.json`.

## Required behavior

- Join every enabled account-aware roster slot on the exact pair
  `(budget_provider, account_id)`.
- Use the matched account's published `quota.status`, `quota.usedPercent`, and
  `quota.validUntil`. Do not recompute a peak from `windows`.
- A usable decision requires all of: fresh top-level snapshot, exact account match,
  `quota.status == "eligible"`, numeric `quota.usedPercent`, and a parseable future
  `quota.validUntil`.
- A missing `account_id`, missing snapshot match, missing/expired `validUntil`, or any
  non-`eligible` status is `health: "unknown"`. It is never 0% and never healthy.
- Never fall back from a missing account match to the provider headline or another
  sibling account. `main` and `cc1` share provider `claude_code` but do not share a
  budget.
- Keep roster capability filtering exactly as it is. Account matching narrows quota
  identity; it does not widen which executables can perform a task.
- Treat the published `selector.env` as data only. If a later launcher uses it, pass
  the map to the process API; never concatenate it into a shell string.

## `$HERD_VAULT/bin/herd-budget`

### 1. MCP fallback must parse only the JSON content block

The new helper keeps `content[0].text` as JSON and may put a human stale warning in
`content[1]`. Replace the current join-all-text fallback in `mcp_call` with:

```jq
if .structuredContent then .structuredContent
else ([.content[]? | select(.type == "text") | .text][0] // "{}"
      | (try fromjson catch {}))
end
```

### 2. Replace provider-window normalization with account decisions

Replace `NORM` with this filter:

```bash
NORM='
  { age: (.ageSeconds // 0),
    stale_flag: (.stale // false),
    aggregate: .aggregateUtilizationPercent,
    generated_at: .generatedAt,
    tokei_route: (.recommendation // null),
    rows: [ (.providers // [])[] as $provider
            | ($provider.accounts // [])[]
            | { provider: $provider.id,
                account_id: (.accountID // null),
                label: (.label // null),
                quota_status: (.quota.status // "unknown"),
                pct: (.quota.usedPercent // null),
                valid_until: (.quota.validUntil // null),
                reason_code: (.quota.reasonCode // null),
                selector: (.selector // null),
                tokens_today: (.tokensToday // null) } ] }'
```

Provider rows without `accounts` intentionally produce no match for an account-aware
slot. If Herdr later needs legacy single-account provider routing, add an explicit
roster mode for it; do not overload a missing `account_id` as permission to fall back.

### 3. Replace the provider-ID join in `ROWS`

Use a composite account index and compute freshness before health:

```bash
ROWS='
  ($roster[0].slots) as $slots
  | ($p.rows
     | map(select(.account_id != null))
     | INDEX(.provider + "\u0000" + .account_id)) as $byaccount
  | (($p.stale_flag) or (($p.age // 0) > $maxage)) as $snapshot_stale
  | [ $slots | to_entries[] | select(.value.enabled) | . as $e
      | ($e.value.budget_provider // "unknown") as $provider
      | ($e.value.account_id // null) as $account_id
      | (if $account_id == null then null
         else $byaccount[$provider + "\u0000" + $account_id] end) as $r
      | (($r.valid_until // "")
         | try fromdateiso8601 catch null) as $valid_until_epoch
      | (($snapshot_stale | not)
         and ($r != null)
         and ($r.quota_status == "eligible")
         and ($r.pct != null)
         and ($valid_until_epoch != null)
         and ($valid_until_epoch > now)) as $decision_fresh
      | { slot: $e.key,
          provider: $provider,
          account_id: $account_id,
          account_match: ($r != null),
          account_label: ($r.label // null),
          quota_status: ($r.quota_status // "unknown"),
          utilization_pct: (if $decision_fresh then $r.pct else null end),
          estimate_pct: (if $r != null and ($decision_fresh | not)
                         then $r.pct else null end),
          valid_until: ($r.valid_until // null),
          reason_code: ($r.reason_code // null),
          selector: ($r.selector // null),
          tokens_today: ($r.tokens_today // null),
          stale: ($snapshot_stale or (($r != null) and ($decision_fresh | not))),
          shared_with: ($e.value.budget_shared_with // null),
          cost_tier: ($e.value.cost_tier // "mid"),
          detection: ($e.value.detection // "unknown"),
          capabilities: $e.value.capabilities,
          health: (if ($decision_fresh | not) then "unknown"
                   elif $r.pct >= $crit then "critical"
                   elif $r.pct >= $warn then "warn"
                   else "healthy" end) } ]'
```

Keep the existing `--route --capability` filter. It may choose only `healthy` or
`warn` rows after this exact-account decision. `critical` remains avoid; `unknown`
remains unknown. Do not use `recommendation.routeTo` or a provider-level window as a
substitute when no exact row is usable.

### 4. Consumer acceptance probes

Add fixture probes that assert:

1. Claude default `unknown` and Claude account-1 `eligible` produce different rows.
2. A roster `account_id` absent from the snapshot stays `unknown`; it never inherits
   its sibling's percentage.
3. `validUntil` one second in the past makes an otherwise eligible row `unknown`.
4. Top-level `stale: true` makes every account decision `unknown`.
5. A selector path containing spaces, quotes, and `$()` remains byte-for-byte JSON
   data and is never executed.
6. `--route --capability` still excludes slots lacking the requested capability.

## `$HERD_VAULT/bin/herd-roster.json`

Add `account_id` to these existing slot objects. The three Codex model seats share
one Codex account and therefore intentionally share one account ID.

```json
{
  "slots": {
    "main": {
      "account_id": "claude_code:57cd1a5e4ea803a4593551fad87d3fb681a5e59414b997f3e3701a3b37ddfb38"
    },
    "cc1": {
      "account_id": "claude_code:fad36634f6ec8d183bccf760424d590c2ea70add6073b19eaee00561f0ca40be"
    },
    "codex": {
      "account_id": "codex:adea4eefd64e54e1502d2fe5c8a42c15c21de0912ff8e5a0b10abc0a186e8ece"
    },
    "sol": {
      "account_id": "codex:adea4eefd64e54e1502d2fe5c8a42c15c21de0912ff8e5a0b10abc0a186e8ece"
    },
    "astra": {
      "account_id": "codex:adea4eefd64e54e1502d2fe5c8a42c15c21de0912ff8e5a0b10abc0a186e8ece"
    }
  }
}
```

These are real IDs captured from the allowed local public snapshot generated at
`2026-09-17T20:51:32Z`. During final verification, the still-running older installed
app rewrote that file at `2026-09-17T21:03:50Z` without the additive account fields;
the new helper correctly returned two legacy Claude rows with `accountID: null`.
Do not infer replacements from paths. The orchestrator must run the new app writer,
then print the IDs through the new bundled helper with this exact sequence:

```bash
cd /Users/abhayp/Downloads/Projects/tokei-worktrees/2026-09-17-mcp-schema-docs/AIUsageDashboard
xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj \
  -scheme AIUsageDashboardApp -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/herd-t10-roster/DerivedData build
osascript -e 'quit app id "ai.padzy.tokei"' || true
open -n /tmp/herd-t10-roster/DerivedData/Build/Products/Debug/Tokei.app

snapshot="$HOME/Library/Application Support/AIUsageDashboard/agent-snapshot.json"
for attempt in {1..60}; do
  if jq -e '[.providers[] | (.accounts // [])[] | .accountID
             | select(type == "string")] | length >= 3' "$snapshot" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

TOKEI_SNAPSHOT_PATH="$snapshot" \
  /tmp/herd-t10-roster/DerivedData/Build/Products/Debug/Tokei.app/Contents/Helpers/tokei \
  status --json \
  | jq -e '{generatedAt, accounts: [.providers[] | .id as $provider
           | (.accounts // [])[]
           | {provider: $provider, label, accountID}]}
          | select([.accounts[].accountID | type == "string"] | all)'
```

The earlier real snapshot contained this mapping; the command above must reproduce
the same values before the roster patch is applied:

```json
{
  "generatedAt": "2026-09-17T20:51:32Z",
  "accounts": [
    {
      "provider": "codex",
      "label": "default",
      "accountID": "codex:adea4eefd64e54e1502d2fe5c8a42c15c21de0912ff8e5a0b10abc0a186e8ece"
    },
    {
      "provider": "claude_code",
      "label": "default",
      "accountID": "claude_code:57cd1a5e4ea803a4593551fad87d3fb681a5e59414b997f3e3701a3b37ddfb38"
    },
    {
      "provider": "claude_code",
      "label": "account-1",
      "accountID": "claude_code:fad36634f6ec8d183bccf760424d590c2ea70add6073b19eaee00561f0ca40be"
    }
  ]
}
```

Do not copy plan names or account ownership claims from the old roster note into
the quota decision. The snapshot proves the identity join and current bounded quota
state; it does not verify billing plan prose.
