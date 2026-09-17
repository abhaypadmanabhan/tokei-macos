# Provider specification

This document describes the current Core model. The public agent wire format is
documented separately in `08-agent-snapshot-schema.md`.

## Provider and quota enums

```swift
enum ProviderID: String {
    case claudeCode = "claude_code"
    case codex, cursor, antigravity, cline, opencode, gemini, copilot
}

enum QuotaWindowType: String {
    case session, daily, weekly, fiveHour, monthly
    case credits, perModel, lifetime
}

enum MetricConfidence: String {
    case exact, providerReported, localParsed, estimated, unavailable
}
```

`exact` and `providerReported` become public `official`; `localParsed` and
`estimated` become `local_estimate`; `unavailable` stays `unavailable`.

## Quota and usage

```swift
struct QuotaWindow {
    let providerID: ProviderID
    let type: QuotaWindowType
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let resetAt: Date?
    let confidence: MetricConfidence
    let source: String
    let label: String?
    let bucketKey: String?
    let observedAt: Date?
}

struct TokenUsage {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheCreationTokens: Int?
    let reasoningTokens: Int?
    var totalTokens: Int? { get }
    let confidence: MetricConfidence
}
```

`observedAt` is when the quota reading was taken; `resetAt` is when its budget
refills. They are not interchangeable. `bucketKey` keeps two windows of the same
type distinct, while `label` is their provider-supplied display name.

## Provider snapshot

```swift
struct ProviderSnapshot {
    let providerID: ProviderID
    let displayName: String
    let authStatus: AuthStatus
    let quotaWindows: [QuotaWindow]
    let todayUsage: TokenUsage
    let weekUsage: TokenUsage
    let monthUsage: TokenUsage?
    let lifetimeUsage: TokenUsage?
    let costUsage: CostUsage?
    let warnings: [ProviderWarning]
    let lastSyncedAt: Date?
    let dailyTotals: [Date: Int]?
    let hourlyTotals: [Date: Int]?
    let accounts: [ProviderAccountUsage]?
    let headlineAccountID: String?
}
```

Provider totals remain aggregates. When `accounts` is present, `todayUsage` is the
sum across accounts and `quotaWindows` comes from the eligible account with the most
headroom. `headlineAccountID` is that row's legacy local ID inside Core; the public
snapshot writer maps it to the stable provider-scoped account ID.

## One account abstraction

All multi-account providers use the same types. Do not create a provider-specific
parallel account hierarchy.

```swift
struct AccountProfile {
    let id: String                 // local profile locator
    let root: URL
    let selector: AccountSelector?
}

struct ProviderAccount {
    let id: String                 // stable provider-scoped account ID
    let providerID: ProviderID
    let legacyID: String
    let label: String
    let profiles: [AccountProfile]
    let preferredProfileID: String
}

struct ProviderAccountUsage {
    let id: String                 // legacy local locator
    let accountID: String?         // stable provider-scoped identity
    let selector: AccountSelector?
    let label: String
    let quotaWindows: [QuotaWindow]
    let todayUsage: TokenUsage
    let dailyTotals: [Date: Int]?
    let configDirectories: [String]
    let unreadableDirectories: [String]
    let quotaStatus: AccountQuotaStatus
    let quotaStatusDetail: String?
}

enum AccountQuotaStatus: String {
    case eligible
    case expiredCredentials
    case cooldown
    case disabled
    case requestFailed
    case noQuotaSource
    case unknown
}
```

`AccountSelector` is literal process data. It currently allowlists exactly one
`CLAUDE_CONFIG_DIR` for Claude or one `CODEX_HOME` for Codex, and only for an
existing absolute directory without control characters. Pass `selector.env` to a
process API as its environment map; never turn it into an `export` or other shell
program.

Known provider identities hash to an opaque ID stable across machines. If the
adapter cannot read an identity, normalization uses a `provider:local:` path hash;
that fallback is stable only for the local canonical root. Unknown identities never
merge merely because both are unknown.

### Adapter coverage

| Provider | Account adapter | Identity and selector |
|---|---|---|
| Claude Code | Multi-account | Discovers the default, sibling, registered, and inherited roots on every refresh; groups known `oauthAccount.accountUuid` identities; selector key `CLAUDE_CONFIG_DIR`. |
| OpenAI Codex | Multi-account | Discovers the default, registered, and inherited Codex homes; reads only nonsecret `tokens.account_id` metadata; selector key `CODEX_HOME`. |
| Cursor | Single-account public view | No account descriptor/selector adapter; provider fields remain the source of truth. |
| Cline / Cline Pass | Single-account public view | No account descriptor/selector adapter. |
| Antigravity | Single-account public view | No account descriptor/selector adapter. |
| opencode | Single-account public view | No account descriptor/selector adapter. |
| Gemini CLI | Single-account public view | No account descriptor/selector adapter. |
| GitHub Copilot | Single-account public view | Install detection only; no local usage/quota account adapter. |

The provider-agnostic `SingleAccountDiscoverer` is available as a compatibility
fallback, but providers without an adapter currently omit public `accounts` rather
than inventing an identity.

## Protocols

These signatures are frozen:

```swift
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func detectAvailability() async -> ProviderAvailability
    func authenticate() async throws -> AuthStatus
    func fetchSnapshot() async throws -> ProviderSnapshot
}

protocol LocalLogProvider: Sendable {
    func discoverLogSources() async throws -> [LogSource]
}

protocol QuotaProvider: Sendable {
    func fetchQuotaWindows() async throws -> [QuotaWindow]
}

protocol TokenUsageProvider: Sendable {
    func fetchTokenUsage(range: UsageRange) async throws -> TokenUsage
}
```

`CalendarAwareProvider` is separate so timezone changes can rebuild cached day
buckets without changing `UsageProvider`.

## Provider rules

- **Claude Code:** local JSONL, per-profile Keychain credentials, and optional
  provider-reported session/weekly/model quota. Partial root failures must stay
  attributable to the affected account.
- **Codex:** local session JSONL and latest applicable rate-limit event per Codex
  home. Session-file ownership must not cross identity transitions.
- **Cursor:** local database fallback; opt-in network adapter may add official usage.
- **Cline:** local session data; subscription quota remains unavailable unless the
  provider exposes a supported source.
- **Antigravity:** local plan/credits plus optional loopback RPC model quota.
- **Gemini:** read-only official CLI credentials and Code Assist quota adapter.
- **opencode:** local store parsing.
- **Copilot:** installation detection only; never invent usage or quota.

## Storage and security

Raw provider responses may be stored only in explicit debug/dev troubleshooting
paths. Release builds must not retain them. Stable account IDs, labels, local paths,
and allowlisted selector environment maps are nonsecret addressing metadata; tokens,
cookies, bearer values, emails, and raw provider identifiers must never enter the
public agent snapshot or logs.
