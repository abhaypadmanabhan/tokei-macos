# Provider Specification

## ProviderID

```swift
enum ProviderID {
    case claudeCode
    case codex
    case cursor
    case antigravity
    case cline
}
```

## QuotaWindowType

```swift
enum QuotaWindowType {
    case session
    case daily
    case weekly
    case monthly
    case credits
    case perModel
    case lifetime
}
```

## MetricConfidence

```swift
enum MetricConfidence {
    case exact
    case providerReported
    case localParsed
    case estimated
    case unavailable
}
```

## QuotaWindow

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
}
```

## TokenUsage

```swift
struct TokenUsage {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheCreationTokens: Int?
    let reasoningTokens: Int?
    let totalTokens: Int?
    let confidence: MetricConfidence
}
```

## ProviderSnapshot

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
}
```

## Protocols

### UsageProvider

```swift
protocol UsageProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func detectAvailability() async -> ProviderAvailability
    func authenticate() async throws -> AuthStatus
    func fetchSnapshot() async throws -> ProviderSnapshot
}
```

### LocalLogProvider

```swift
protocol LocalLogProvider {
    func discoverLogSources() async throws -> [LogSource]
}
```

### QuotaProvider

```swift
protocol QuotaProvider {
    func fetchQuotaWindows() async throws -> [QuotaWindow]
}
```

### TokenUsageProvider

```swift
protocol TokenUsageProvider {
    func fetchTokenUsage(range: UsageRange) async throws -> TokenUsage
}
```

## Provider-Specific Rules

### Claude Code
- Parse local JSONL from `~/.claude/projects/<encoded-project-path>/<session-id>.jsonl`.
- Extract usage from assistant message `usage` blocks.
- Deduplicate by message/request/session ID.
- Stream large files; do not load entirely into memory.
- Confidence for parsed values: `localParsed`.
- Session/weekly limits are `unavailable` unless a private endpoint is implemented later.

### OpenAI Codex
- Detect `~/.codex/auth.json` and local Codex logs if available.
- Adapter may attempt safe provider sync; keep endpoint logic isolated.
- Many metrics will be `unavailable` or `estimated` in MVP.

### Cursor
- Detect local `state.vscdb` and read `cursorAuth/accessToken` if possible.
- Model usage as monthly budget: included, bonus, on-demand.
- Do not force session/weekly model.
- Endpoint adapter is separate and optional.

### Cline / Cline Pass
- Web dashboard at `https://app.cline.bot/dashboard/subscription`.
- Treat as credits quota window.
- Local extension state detection is optional.
- Most metrics are `unavailable` in MVP.

### Antigravity
- Skeleton only in MVP.
- Support per-model quota window type in the model layer.
- Document research TODOs in code comments.

## Raw Response Storage

Raw provider responses may be stored only in debug/dev builds for troubleshooting. Storage must be opt-in and clearly labeled. Release builds must not retain raw responses.

## Confidence Defaults

- Exact computed values: `exact`.
- Values returned by provider endpoint: `providerReported`.
- Values parsed from local logs: `localParsed`.
- Values inferred from partial data: `estimated`.
- Values with no source: `unavailable`.
