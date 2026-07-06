# Architecture: AI Usage Dashboard

## High-Level Layers

```
UI Layer (SwiftUI)
├── Dashboard
├── MenuBarExtra
├── ProviderDetail
├── Settings
└── Widgets

View Model Layer
├── DashboardViewModel
└── MenuBarViewModel

Sync Layer
├── SyncEngine
├── FSEvents/File Watcher
└── Background Refresh

Provider Layer
├── ProviderRegistry
├── UsageProvider protocol
├── LocalLogProvider protocol
├── QuotaProvider protocol
├── TokenUsageProvider protocol
└── Provider Adapters (Claude, Codex, Cursor, Cline, Antigravity)

Storage Layer
├── SwiftData / SQLite persistence
├── UsageStore
└── Debug raw-response store (dev only)

Security
├── Keychain credential storage
└── No secrets in UserDefaults or plain files

Notifications
├── NotificationEngine
└── Threshold rules
```

## Data Flow

1. UI calls View Model.
2. View Model calls SyncEngine.
3. SyncEngine calls one or more providers.
4. Each provider returns a normalized `ProviderSnapshot`.
5. SyncEngine persists snapshots to the storage layer.
6. View Model publishes snapshots to the UI.
7. NotificationEngine evaluates thresholds and emits notifications.
8. FSEvents watcher triggers incremental refreshes when local logs change.

## Key Rule: No UI-to-Provider Direct Calls

All provider interaction is routed through the SyncEngine. This keeps UI code small, testable, and safe. The UI layer must never call provider functions directly.

## Provider Normalization

Each provider adapter is responsible for:
- Detecting whether the provider is installed/authenticated.
- Reading local data where available.
- Optionally fetching private/provider endpoint data.
- Returning a `ProviderSnapshot` with normalized `QuotaWindow` and `TokenUsage` values.
- Tagging every metric with the correct `MetricConfidence`.
- Storing raw provider responses only in debug/dev builds.

## Persistence

The storage layer uses SwiftData with a SQLite backing store. It stores:
- Provider snapshots.
- Historical token usage per day/week/month.
- Threshold settings.
- Raw provider responses (debug builds only).

## Concurrency

- Use Swift Concurrency (`async`/`await`) throughout.
- Run file watchers and background sync on dedicated queues/actors.
- Main actor is only used for UI updates.

## Security

- Credentials are stored in the Keychain.
- No secrets are written to UserDefaults or plain files.
- Raw response debug storage is opt-in and never leaves the device.

## Quota Model

Quota windows are provider-specific. A `QuotaWindow` can represent any of:
- `session`
- `daily`
- `weekly`
- `monthly`
- `credits`
- `perModel`
- `lifetime`

The UI renders windows generically; it does not assume every provider has a session limit.

## Parsing

- Large JSONL files are streamed, not loaded entirely into memory.
- Parsing is defensive: unknown fields are ignored, malformed lines are skipped, and errors are surfaced as warnings rather than crashes.
- Claude entries are deduplicated by message/request/session ID where possible.

## Widgets

Widgets are implemented as a WidgetKit extension. They read the latest persisted snapshot from shared storage (App Group container) and display a compact summary.
