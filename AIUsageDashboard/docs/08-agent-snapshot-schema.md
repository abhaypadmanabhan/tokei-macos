# 08 · Agent snapshot schema + `tokei` helper (#57)

Tokei exposes the quota data it already computes to orchestrating agents so they
can route work to an exact provider account without guessing from a label or path.
The v1 surface is read-only: the app atomically writes a snapshot and the bundled
`tokei` helper reads it.

## 1. Snapshot file

- **Path:** `~/Library/Application Support/AIUsageDashboard/agent-snapshot.json`
- **Writer:** `AgentSnapshotWriter`, after each `SyncEngine.refreshAll()` cycle.
- **Write contract:** atomic replacement; a reader sees the old complete file or the
  new complete file, never a torn intermediate file.
- **Schema version:** `1`. The account additions are optional additive fields, not a
  breaking shape change.

### Security invariant

The file may contain percentages, token counts, timestamps, bounded status codes,
opaque account IDs, human labels, local profile paths, and allowlisted process
environment selectors. It must never contain a credential, token, cookie, bearer,
email address, raw provider identity, arbitrary diagnostic, or provider response.

`accountID` is a SHA-256-derived opaque provider-scoped key. A selector is addressing
data such as `{"env":{"CODEX_HOME":"/Users/me/.codex"}}`, not a shell program.

## 2. Two-account example

This is the account-aware subset of the two-Claude-account contract fixture from
the WP-6 research (`artifacts/t03/schema-after.json`); shown values are exact and
unrelated unchanged fields are omitted. IDs and values are deterministic synthetic
fixture data, not a claim about the current machine.

```jsonc
{
  "schemaVersion": 1,
  "generatedAt": "2026-09-17T02:16:40Z",
  "aggregateUtilizationPercent": 56,
  "providers": [
    {
      "id": "claude_code",
      "displayName": "Claude Code",
      "lastUpdated": "2026-09-17T02:16:39Z",
      "tokensToday": 553069448,
      "windows": [
        {
          "type": "session",
          "usedPercent": 9,
          "confidence": "official",
          "source": "api.anthropic.com/api/oauth/usage",
          "observedAt": "2026-09-17T02:14:00Z",
          "resetsAt": "2026-09-17T03:40:00Z"
        },
        {
          "type": "weekly",
          "usedPercent": 81,
          "confidence": "official",
          "source": "api.anthropic.com/api/oauth/usage",
          "observedAt": "2026-09-17T02:14:00Z",
          "resetsAt": "2026-09-21T01:59:59Z"
        },
        {
          "type": "perModel",
          "usedPercent": 81,
          "confidence": "official",
          "source": "api.anthropic.com/api/oauth/usage",
          "observedAt": "2026-09-17T02:14:00Z",
          "resetsAt": "2026-09-21T01:59:59Z"
        }
      ],
      "accounts": [
        {
          "id": "/Users/abhayp/.claude",
          "accountID": "claude_code:c99dd9a2310dcd8ac8bf64432cf3e2b91b51e9488e15ccffbdcc681be8792ec2",
          "label": "default",
          "selector": {
            "env": { "CLAUDE_CONFIG_DIR": "/Users/abhayp/.claude" }
          },
          "windows": [],
          "tokensToday": 0,
          "quota": {
            "status": "unknown",
            "reasonCode": "no_quota_reading"
          }
        },
        {
          "id": "/Users/abhayp/.claude-account-1",
          "accountID": "claude_code:41b5e8112aea16297b2abf8229b1c429ead077faecea1ea4f904ea26ee76a2e4",
          "label": "account-1",
          "selector": {
            "env": { "CLAUDE_CONFIG_DIR": "/Users/abhayp/.claude-account-1" }
          },
          "windows": [
            {
              "type": "session",
              "usedPercent": 9,
              "confidence": "official",
              "source": "api.anthropic.com/api/oauth/usage",
              "observedAt": "2026-09-17T02:14:00Z",
              "resetsAt": "2026-09-17T03:40:00Z"
            },
            {
              "type": "weekly",
              "usedPercent": 81,
              "confidence": "official",
              "source": "api.anthropic.com/api/oauth/usage",
              "observedAt": "2026-09-17T02:14:00Z",
              "resetsAt": "2026-09-21T01:59:59Z"
            },
            {
              "type": "perModel",
              "usedPercent": 81,
              "confidence": "official",
              "source": "api.anthropic.com/api/oauth/usage",
              "observedAt": "2026-09-17T02:14:00Z",
              "resetsAt": "2026-09-21T01:59:59Z"
            }
          ],
          "tokensToday": 553069448,
          "quota": {
            "status": "eligible",
            "usedPercent": 81,
            "headroomPercent": 19,
            "bindingWindowIndex": 1,
            "validUntil": "2026-09-17T02:26:40Z"
          }
        }
      ],
      "headlineAccountID": "claude_code:41b5e8112aea16297b2abf8229b1c429ead077faecea1ea4f904ea26ee76a2e4"
    },
    {
      "id": "codex",
      "displayName": "OpenAI Codex",
      "windows": [
        {
          "type": "weekly",
          "usedPercent": 31,
          "confidence": "official",
          "source": "Codex CLI rate_limits (pro plan, weekly window)",
          "observedAt": "2026-09-17T02:14:00Z",
          "resetsAt": "2026-09-21T05:26:47Z"
        }
      ],
      "accounts": [
        {
          "id": "/Users/abhayp/.codex",
          "accountID": "codex:a0aba5417af6496ff20d401d87bfb39c579039a08de804bbfe225a18e8c41e25",
          "label": "default",
          "selector": { "env": { "CODEX_HOME": "/Users/abhayp/.codex" } },
          "windows": [
            {
              "type": "weekly",
              "usedPercent": 31,
              "confidence": "official",
              "source": "Codex CLI rate_limits (pro plan, weekly window)",
              "observedAt": "2026-09-17T02:14:00Z",
              "resetsAt": "2026-09-21T05:26:47Z"
            }
          ],
          "tokensToday": 121521151,
          "quota": {
            "status": "eligible",
            "usedPercent": 31,
            "headroomPercent": 69,
            "bindingWindowIndex": 0,
            "validUntil": "2026-09-17T02:26:40Z"
          }
        }
      ],
      "headlineAccountID": "codex:a0aba5417af6496ff20d401d87bfb39c579039a08de804bbfe225a18e8c41e25"
    }
  ],
  "recommendation": {
    "routeTo": "codex",
    "avoid": [],
    "reason": "route to OpenAI Codex (tightest window 31%)",
    "target": {
      "provider": "codex",
      "accountID": "codex:a0aba5417af6496ff20d401d87bfb39c579039a08de804bbfe225a18e8c41e25",
      "selector": { "env": { "CODEX_HOME": "/Users/abhayp/.codex" } }
    },
    "avoidAccounts": [],
    "validUntil": "2026-09-17T02:26:40Z"
  }
}
```

## 3. Field reference

### Snapshot and provider

| Field | Meaning |
|---|---|
| `schemaVersion` | Wire shape version. Remains `1` for these optional additions. |
| `generatedAt` | When the app wrote the file, UTC ISO8601. |
| `providers[]` | Provider rows. |
| `aggregateUtilizationPercent` | Mean of applicable provider peaks; absent if none are computable. |
| `recommendation` | Shared routing decision; absent if no decision was publishable. |
| `providers[].id` | Stable provider ID such as `claude_code` or `codex`. |
| `displayName` | Human provider name. |
| `windows` | The provider headline account's public windows, or the provider windows when no account breakdown exists. |
| `tokensToday` | Provider total; for multi-account providers this is the sum. |
| `lastUpdated` | When that provider last synchronized. |
| `accounts` | Optional per-account rows. Providers without an account adapter omit it rather than emit an invented account. |
| `headlineAccountID` | Stable `accountID` whose trusted quota produced the provider headline. |

### Account

| Field | Meaning |
|---|---|
| `accounts[].id` | Legacy local locator, currently a profile path. It is retained for compatibility and is not a portable identity. |
| `accountID` | Opaque provider-scoped identity. Stable across machines when the adapter knows the provider identity; a `:local:` fallback is machine/path scoped. |
| `label` | Human label such as `default` or `account-1`; never use it as identity. |
| `windows` | This account's public quota windows. Empty means no computable window, not 0% use. |
| `tokensToday` | Tokens attributed to this account today, when derivable. |
| `selector.env` | Allowlisted literal process environment map: one `CLAUDE_CONFIG_DIR` or `CODEX_HOME`. It may be absent. |
| `quota.status` | Bounded account state described below. |
| `quota.usedPercent` | Peak applicable window, even when an untrusted reading makes the decision unknown. |
| `quota.headroomPercent` | `100 - usedPercent`; emitted only for trusted, fresh, complete `eligible` decisions. |
| `quota.bindingWindowIndex` | Index into this account's emitted `windows` array that supplied `usedPercent`. |
| `quota.validUntil` | Latest instant at which this account decision may be used. Present only for eligible decisions. |
| `quota.reasonCode` | Bounded explanation for `unknown`: currently `no_quota_reading` or `untrusted_reading`. |

`quota.status` meanings:

| Code | Consumer meaning |
|---|---|
| `eligible` | Trusted, fresh, complete quota is usable until `validUntil`. |
| `expiredCredentials` | Credentials are known expired; reauthenticate with the provider CLI. |
| `cooldown` | Provider account is in a bounded cooldown state. |
| `disabled` | The account's quota path is disabled. |
| `requestFailed` | The most recent provider quota request failed. |
| `noQuotaSource` | This adapter has no supported account quota source. |
| `unknown` | No complete trusted decision is available; absence is not headroom. |

### Window

| Field | Meaning |
|---|---|
| `type` | `session`, `daily`, `weekly`, `fiveHour`, `monthly`, `credits`, `perModel`, or `lifetime`. |
| `usedPercent` | Used fraction, clamped to 0–100. |
| `resetsAt` | When the budget refills, if known. |
| `confidence` | `official`, `local_estimate`, or `unavailable`. |
| `source` | Bounded diagnostic source label. |
| `observedAt` | When the reading was taken; use this for reading freshness. |
| `label` | Optional provider display label for a bucket. |
| `bucketKey` | Optional stable identity separating multiple same-type buckets. |

### Recommendation

| Field | Meaning |
|---|---|
| `routeTo` | Legacy provider projection of the target; absent or `null` means no target. |
| `avoid` | Provider IDs whose provider-level decision is over the avoid threshold. |
| `reason` | Human explanation, not an input for policy parsing. |
| `target.provider` | Provider ID for the exact account target. |
| `target.accountID` | Stable account identity to join against `providers[].accounts[]`. |
| `target.selector` | Verified literal process selector, when Tokei can publish one. |
| `avoidAccounts[]` | Exhausted sibling account references as `{provider, accountID}`. |
| `validUntil` | Expiry for `routeTo` and `target`. Consumers must reject the decision after it. |

To execute a target, pass `target.selector.env` as the environment dictionary to a
process-spawn API. Never concatenate a selector value into a shell command. A target
with no selector is advisory identity only; do not guess a path from its label.

## 4. Freshness and expiry

There are three different clocks:

1. `generatedAt` / reader-computed `ageSeconds`: file age.
2. `windows[].observedAt`: provider reading age.
3. `quota.validUntil` and `recommendation.validUntil`: decision expiry.

`SnapshotReader` always computes top-level `ageSeconds` and `stale` from its own
clock. File age over 600 seconds is stale; exactly 600 seconds is still fresh;
future clock skew clamps age to zero. It then applies the shared Foundation-only
recommendation validity helper. After `recommendation.validUntil`, the helper drops
`routeTo` and `target`, preserves historical windows/avoid data, and appends
`recommendation expired` to the reason. It never re-ranks.

The `get_route_recommendation` projection is always JSON and adds `generatedAt`,
`ageSeconds`, `validUntil`, and `stale`. Its `stale` is true if either the whole file
is stale or the recommendation has expired. `content[0].text` remains parseable JSON;
when the file itself is stale, `content[1]` may carry a human warning.

## 5. Compatibility and upgrades

- Optional fields are omitted when absent. Missing `accountID`, `selector`, `quota`,
  `headlineAccountID`, `target`, `avoidAccounts`, `validUntil`, `label`, or
  `bucketKey` means unknown/unsupported, never a default value.
- Consumers must feature-detect `accountID` and `target`; `schemaVersion == 1` alone
  does not prove the producer is account-aware.
- `accounts[].id` keeps its legacy path meaning. Do not silently reinterpret it as an
  opaque identity.
- New readers accept legacy 0.8.0 snapshots with none of the additions and accept
  unknown fields from newer additive writers.
- Old Swift helpers decode new keys but discard them when they re-encode. An older
  helper in front of a newer app is therefore a **lossy proxy**.
- Ship the helper and app together. Updating only the app can make the raw file
  account-aware while MCP output from the old helper is not.

## 6. `tokei` helper and MCP

The standalone helper is bundled at `Tokei.app/Contents/Helpers/tokei`. It compiles
the shared Foundation-only schema/expiry source directly and does not link the app
framework.

```sh
tokei status
tokei status --json
tokei mcp
tokei version
```

Missing, unreadable, and malformed snapshots exit 3, 4, and 5 respectively for
`status`; stale reads still exit 0 and identify themselves. `TOKEI_SNAPSHOT_PATH`
may point the helper at a fixture.

The newline-delimited JSON-RPC server exposes exactly two read-only tools:

| Tool | Result in `content[0].text` |
|---|---|
| `get_usage` | Full snapshot with reader-side `stale` and `ageSeconds`. |
| `get_route_recommendation` | Flat recommendation plus `generatedAt`, `ageSeconds`, `validUntil`, and `stale`. |

Both tool descriptions document the account contract and quota status codes. The
server performs no network or credential access.

## 7. Registration

```sh
claude mcp add tokei -- /Applications/Tokei.app/Contents/Helpers/tokei mcp
```

```toml
[mcp_servers.tokei]
command = "/Applications/Tokei.app/Contents/Helpers/tokei"
args = ["mcp"]
```

## Out of scope

Write-back, per-agent run logging, a wake-the-app refresh, HTTP transport, and an
`.mcpb` bundle remain outside v1.
