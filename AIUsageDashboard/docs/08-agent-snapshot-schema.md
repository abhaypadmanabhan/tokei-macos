# 08 · Agent snapshot schema + `tokei` helper (#57)

Tokei exposes the quota data it already computes to orchestrating agents (Claude
Code, Codex CLI, …) so they can route work away from a near-exhausted provider.
Read-only in v1: the app writes a snapshot file; a bundled `tokei` helper reads it.

## 1. The snapshot file

- **Path:** `~/Library/Application Support/AIUsageDashboard/agent-snapshot.json`
- **Writer:** `AgentSnapshotWriter` (Core), invoked from `SyncEngine.refreshAll()`
  after every refresh cycle. Written **atomically** (`Data.write(options: .atomic)`),
  so a reader never sees a torn file and a crash mid-write keeps the prior snapshot.
- **Producer of the shape:** `AgentSnapshotWriter.buildSnapshot(from:generatedAt:)` —
  pure, so the mapping is unit-tested without disk.

### Security invariant

**Only percentages, token counts, and timestamps.** No tokens, cookies, bearers,
CSRF, or credentials of any kind. The schema types (`AgentSnapshot` &co.) carry
nothing else, and a unit test (`testEncodedSnapshotContainsNoSecretShapedFields`)
guards against a secret-shaped field creeping in.

### Schema (v1)

```jsonc
{
  "schemaVersion": 1,
  "generatedAt": "2026-07-24T09:12:00Z",   // UTC, ISO8601, when the app wrote it
  "providers": [
    {
      "id": "claude_code",                 // ProviderID.rawValue (stable machine id)
      "displayName": "Claude Code",
      "windows": [
        {
          "type": "fiveHour",              // QuotaWindowType.rawValue: session | daily |
                                           //   weekly | fiveHour | monthly | credits |
                                           //   perModel | lifetime
          "usedPercent": 42.0,             // 0…100, clamped
          "resetsAt": "2026-07-24T12:00:00Z", // omitted if the provider doesn't report it
          "confidence": "official",        // official | local_estimate | unavailable
          "source": "oauth_usage_api"      // diagnostic label
        }
      ],
      "tokensToday": 1834000,              // omitted if not derivable
      "lastUpdated": "2026-07-24T09:11:40Z"
    }
  ],
  "aggregateUtilizationPercent": 61.5,     // peak-per-provider, averaged; omitted if none
  "recommendation": {                      // omitted when there isn't enough signal
    "routeTo": "codex",                    // least-utilized provider, or null
    "avoid": ["antigravity"],              // providers at/over 85% utilization
    "reason": "antigravity weekly 92% used, resets in 3h; route to OpenAI Codex (tightest window 31%)"
  }
}
```

Fields are **omitted when absent** (not `null`), except `recommendation.routeTo`
which is explicitly nullable.

#### Reader-computed staleness (never written to disk)

The helper stamps two extra top-level fields when it emits a response, so a stale
snapshot is never served silently:

| field        | meaning                                                          |
|--------------|------------------------------------------------------------------|
| `stale`      | `true` when `age > 600s` (10 min). Covers "app not running" too. |
| `ageSeconds` | whole seconds between `generatedAt` and now (clamped ≥ 0).        |

### Confidence mapping (internal → public)

| internal `MetricConfidence`      | public `confidence` |
|----------------------------------|---------------------|
| `exact`, `providerReported`      | `official`          |
| `localParsed`, `estimated`       | `local_estimate`    |
| `unavailable`                    | `unavailable`       |

Agents must **not** treat `local_estimate` / `unavailable` values as hard limits.

### Versioning

`schemaVersion` bumps only on a non-additive change. Readers should tolerate an
unknown newer version by reading the fields they understand. Adding an optional
field is additive and does **not** bump the version.

## 2. `tokei` helper

Bundled at `Tokei.app/Contents/Helpers/tokei`. Standalone executable — it does **not**
link the app framework; it compiles in the shared public schema file directly and
reads the snapshot only (no network, no Keychain, no other apps' files).

```
tokei status          # human-readable table
tokei status --json   # the raw snapshot (with stale/ageSeconds), for scripting
tokei mcp             # stdio MCP server
tokei help
tokei version
```

- **Missing file** (app never launched) → clear error + launch instructions, exit 3.
- **Stale** → still succeeds (exit 0); the table shows a `⚠︎ STALE` banner and JSON
  carries `"stale": true`.
- `TOKEI_SNAPSHOT_PATH=<file>` overrides the snapshot location (tests / power users).

### MCP server (`tokei mcp`)

Newline-delimited JSON-RPC 2.0 over stdio — the transport every major client
supports without caveats. Dependency-free (read-only, no network; the MCP Swift SDK
would buy nothing). Exactly two tools, to keep an agent's context cost low:

| tool                       | returns                                             |
|----------------------------|-----------------------------------------------------|
| `get_usage`                | the full snapshot (with staleness)                  |
| `get_route_recommendation` | the `recommendation` object only                    |

When the snapshot is stale, tool text is prefixed with a `⚠︎` warning line. When the
file is missing, the tool call returns `isError: true` with launch instructions.

## 3. Registration (agent side)

**Claude Code:**
```
claude mcp add tokei -- /Applications/Tokei.app/Contents/Helpers/tokei mcp
```

**Codex CLI** (`~/.codex/config.toml`):
```toml
[mcp_servers.tokei]
command = "/Applications/Tokei.app/Contents/Helpers/tokei"
args = ["mcp"]
```

**Non-MCP steering** (CLAUDE.md / AGENTS.md):
> Before spawning or delegating to another coding agent, run
> `/Applications/Tokei.app/Contents/Helpers/tokei status --json` and avoid providers
> above 85% utilization.

## 4. Recommendation semantics

`AgentRecommendationEngine` (Core, pure) mirrors the least-filled-provider logic
behind the human-facing "Route work here" chip (`MaxxerMath.routeTarget`, #37). It
takes each provider's **peak** window utilization, then:

- `avoid` = every provider at/over **85%** (issue-specified), tightest first.
- `routeTo` = the least-utilized provider, only when ≥ 2 providers reported quota
  **and** the least one is below 85% (so it never routes you into a wall).
- returns `nil` when there's nothing worth saying (< 2 readings and nothing to avoid).

> FOLLOW-UP: `MaxxerMath` lives under `UI/` and isn't compiled into Core, so the two
> engines are separate today. When `MaxxerMath` moves into Core, collapse them into
> one so the chip and the snapshot are guaranteed identical.

## Out of scope (v1)

Settings "Agent Access" UI section (copy-paste install cards) — owned by a dedicated
UI package. Write-back / per-agent run logging (#42), wake-the-app fresh fetch, HTTP
transport, `.mcpb` bundle.
