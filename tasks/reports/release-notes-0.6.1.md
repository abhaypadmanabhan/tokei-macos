## Tokei 0.6.1

**Fixes the P0 overheating.** Tokei no longer pegs CPU in the background: idle (menu-bar, window closed) now sits at **0%** (was ~20–24%). The cause was the dashboard's retained view graph re-rendering per-second countdowns and charts even when off screen — now gated on window visibility.

### Fixed
- **App no longer overheats the machine** — idle CPU ~20–24% → **0%** (off-screen render gate).
- **Parser CPU on large logs** — Claude + Codex JSONL parsers cache per-file aggregates and resume from byte offset instead of full-re-parsing every sync; cache is bounded (evicts stale files).
- **Cursor cooldown** keyed by durable account id — a 429 on one account no longer blocks another, and a token refresh keeps the same cooldown (#49).

### Added
- **Plan-cost presets + Cursor plan detection** — a preset picker prefills your monthly price; a detected plan is badged and never overwrites a value you typed (#51).

### Docs
- **Gemini**: how to enable quota (one-time `gemini` CLI sign-in) + token-refresh recovery (#54).

_Requires macOS 14+ · Apple Silicon._
