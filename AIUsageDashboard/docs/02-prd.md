# Product Requirements Document: AI Usage Dashboard

## Overview

A native macOS app that tracks AI coding tool usage across multiple providers in one place: a dashboard, menu bar extra, and widgets. The app is local-first, honest about data confidence, and respects provider differences.

## Goals

1. Show users how much they are using each AI coding tool.
2. Surface limits and reset windows so users can plan usage.
3. Alert users when they are close to a limit.
4. Provide glanceable data from the menu bar and WidgetKit widgets.
5. Never misrepresent estimates as exact provider numbers.

## Target Providers

1. Anthropic Claude Code
2. OpenAI Codex
3. Cursor
4. Antigravity
5. Cline / Cline Pass

## Core Metrics

- Current session usage and limit
- Session reset time
- Weekly usage and limit
- Weekly reset time
- Daily tokens used
- Weekly tokens used
- Monthly tokens used if available
- Lifetime tokens used
- Input/output/cache/reasoning tokens where available
- Credits or spend where available

## User Stories

- As a developer, I can open the app and see a dashboard of all providers.
- As a developer, I can see a menu bar item with a quick summary of the most critical provider.
- As a developer, I can click a provider card to see detail about quota windows and token usage.
- As a developer, I can see confidence labels next to every number.
- As a developer, I can set a threshold and receive a notification when a provider is close to a limit.
- As a developer, I can see today's usage in a widget on my desktop.

## Confidence Display

Every metric must show:
- A human-readable confidence badge.
- A tooltip or hint explaining the source (local file, provider endpoint, estimate, etc.).
- A fallback state when a metric is unavailable.

## MVP Scope

### Must-have
- Native macOS SwiftUI app shell with menu bar item and dashboard.
- Provider cards for all five providers.
- Claude Code local JSONL parser.
- Skeleton providers for Codex, Cursor, Cline, and Antigravity.
- Local persistence skeleton.
- Clear confidence labels.
- Widget skeleton.
- Tests for core models and the Claude parser.

### Should-have
- Codex local detection.
- Cursor local detection.
- FSEvents watcher for Claude logs.
- Basic notification threshold model.

### Not MVP
- Full reverse engineering of every private endpoint.
- Monetization or billing.
- App Store sandbox compliance beyond reasonable defaults.
- Full OAuth flow.
- Browser extension.
- Perfect lifetime accounting for logs that no longer exist.

## Success Criteria

- The app builds and runs on macOS 14+.
- Menu bar and dashboard render without crashing.
- Claude parser produces correct token totals from sample JSONL fixtures.
- All provider snapshots carry confidence labels.
- Unit tests pass.

## Open Questions

- Which exact Codex local paths are stable across versions?
- What is the Cursor dashboard endpoint shape and cookie lifetime?
- Does Cline expose any local extension state beyond the web dashboard?
- What is the Antigravity usage/quota model?
