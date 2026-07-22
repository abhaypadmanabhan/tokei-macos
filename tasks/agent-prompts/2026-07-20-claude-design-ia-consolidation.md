# Claude Design prompt — Tokei dashboard IA consolidation (2026-07-20)

Paste the block below into Claude Design. Padzy-OS "aitracker" theme is inlined
verbatim (Claude Design cannot run the internal skill). Mobbin references are
cited per-pattern. Companion to WP-4 (`patch/2026-07-19/ui-ia-consolidation`).

---

Design a desktop dashboard for **Tokei** — a local-first macOS app that tracks how much you're using the AI coding agents you pay for (Claude Code, Codex, Cursor, Cline, Antigravity, Gemini, opencode). Single-user, always-running, menu-bar-resident. The product question it answers: **"am I actually using the tokens I pay for?"**

Build it as a responsive dark web mockup (macOS window, ~1280×800 down to ~720×560). Interactive HTML/React is preferred over static images so I can click the tabs and chips.

## The problem I'm fixing

The current build has a 230pt left sidebar with ~10 rows: Overview, Value, seven provider rows, Settings. That's navigation chrome eating the space that should hold data — and the provider rows are wrong in kind: providers are *data entities*, not places. Value is a *lens* on the same data as Overview, not a separate destination. I want an experienced data-analyst's dashboard: dense, spatially efficient, no wasted chrome.

## Required information architecture

1. **No sidebar at all.** Full-window content.
2. **Two in-content tabs**, top-left, styled as numbered mono kickers: `01 / OVERVIEW` and `02 / VALUE`. Active tab carries a 2px accent tick.
3. **Provider chip strip** directly beneath the tabs: one compact chip per agent — small provider glyph + name + ONE live mono stat (today's tokens, or tightest quota %). Chips convey status ambiently. Trailing **`+` chip** opens "Add agent". Clicking a chip drills into that provider's detail.
4. **Provider detail = drill-in**, not a nav destination: back affordance, provider KPI header, its quota windows and token history.
5. **Settings = gear icon, top-right.** A utility, not a destination.
6. **One time-range control** governing the pane (Today / Week / Month / All-time), top-right.

## Screens to produce

- **A. Overview tab, populated** — the hero. Chip strip, KPI row, main chart, per-agent table.
- **B. Value tab** — headline "plan value multiple" (e.g. `3.4×`) + a status tier chip (tiers: IDLE / WARMING / BREAK-EVEN / MAXXING / GOBLIN MODE), then a dense per-agent table: plan $, API-equivalent $, multiple, confidence badge. Agents with usage but no plan cost set are named in a caption and excluded from the total — show that honestly.
- **C. Provider drill-in** (pick Claude Code): back affordance, quota windows with reset countdowns, token split (input / cache-read / cache-write / output), daily history.
- **D. Empty state** — no agents connected yet. Must lead with the `+`, never a blank strip.
- **E. Narrow window** (~720pt) — show how the chip strip and tables degrade. Wrap, don't truncate.

## Design system — Padzy OS, "aitracker" theme (follow exactly)

**Color** (dark only, no light mode):
- ground `#131316` · surface `#1D1D22` · ink `#ECECF1` · muted `#6E6E78`
- ONE accent: `#FF3B70` — spent **only** on active state and the single primary action per surface. Never decoration. **Dollar values render in ink, never accent** — they're data, not alerts.

**Type**: monospace for every number and data value (token counts, dollars, percentages, dates). Display/sans for headings and prose. Numbered mono kickers label every section (`01 / OVERVIEW`, `02 / VALUE`, `03 / HISTORY`).

**Form**: no shadows. No gradients. No rounded card grids. Border radius ≤ 4px. Structure is expressed as exposed 1px hairlines, not floating cards. 2px accent tick marks active state. Premium macOS density — not a generic SaaS template.

**Honesty rules** (these are product-critical, not decorative):
- Unknown values render as `—`, never a confident `$0` or `0×`.
- Every metric carries a confidence badge: `reported` / `local` / `estimated` / `unavailable`.
- Every surface needs real empty, loading, and error states — design them, don't skip them.

## Mobbin references — take the named pattern from each, not the visual style

- **In-content tab pills** (the core move): StackAI — https://mobbin.com/screens/03fb91f0-89d0-45e6-ada1-34d533a3febf
- **KPI tiles that double as chart selectors** (best space trick — click a stat, the chart below switches): Vercel Analytics — https://mobbin.com/screens/900542f7-c157-4445-8f88-d79dca719c7a
- **Chip/filter row under the header**: LangSmith Monitoring — https://mobbin.com/screens/b7b317f3-20b0-4cf6-86af-c10ae16d0681
- **Inline segmented time-range control**: Posh — https://mobbin.com/screens/a5dfb295-302e-4298-83e0-d78a646e2c15
- **Dense small-multiples grid + inline stat header for LLM/token metrics** (closest analogue to Tokei's data): Adaline — https://mobbin.com/screens/d5b2ad2a-dd83-4d6b-86fa-6edeee1991cd
- **Underline tabs inside a monitoring pane + compact control row**: Neon — https://mobbin.com/screens/cf45e7bf-4a0e-40cc-9db5-a29845b58d4e
- **Mixed tile sizes: big single-number tiles beside chart tiles**: Sentry — https://mobbin.com/screens/ac81ee7f-550f-4395-aafe-13da3dc10e05

Borrow the **structure** from these. Do not borrow their color, rounding, or shadow language — the Padzy tokens above win every conflict.

## Real data to populate with (my actual numbers — makes the density judgeable)

- Claude Code — $200/mo (2× Max accounts), ~533M tokens today, weekly quota 46% used
- Codex — $20/mo, session + weekly quota windows, cost estimated
- Cursor — $20/mo, 1.38M tokens today, quota 7%, "Pro (active)"
- Cline — $5/mo (Cline Pass), real local dollar cost, lifetime tokens
- Antigravity — $5/mo (Google student), quota % only, **no token count exists** — must render `—` with an `unavailable` badge
- Gemini — quota % only, not signed in → clean empty state
- Lifetime across all: ~2.8B tokens

## What I'm judging

Space efficiency and information hierarchy above all. I want to open this and read my whole AI-spend situation in one glance without navigating. Show me two or three genuinely different layout directions for the Overview tab before you commit to one — I care most about how the chip strip, KPI row, and main chart share the vertical budget.
