# WP-3 captures

Own-window captures of the Debug build (`screencapture -x -o -l<window>`, never the full screen), dark only (the
aitracker theme has no light mode). Captures `01`–`09` and `12` come from one live tour of the build at `007d43c`
(2026-10-29 02:01, load average 3.6, `/tmp/tokei-live-proof.lock` held): window on screen 0.7 s after launch,
`01` taken at 2.6 s, first live sync wrote the store at 88.4 s. `10` and `11` were retaken at `4dc66c8` with
one-route launches (`build/proof/route-shot.sh`) after the fixes they show. Fix round 1: `05` and `06` were retaken on
the build merged with dev at `c0858b3` (2026-10-29 02:35, live sync at 113 s); the other ten are unchanged. All pass the flat-colour check
(`build/proof/blankcheck.sh`, content standard deviation well above 0.004). Numbers are Abhay's real local data.
Extra usage and the `@fast` tier key come from Debug fixtures, because WP-4 and WP-1 are not on this branch.

| File | What it shows |
|---|---|
| `01-cold-launch-2.5s.png` | AC1. Cold launch, 2.6 s: the saved numbers are on screen at once ("543M tokens today … saved 4 min ago · updating…"), with no blank "Reading local logs" page. Before WP-3, first numbers took 66 s (Bible §0). |
| `02-after-live-sync.png` | AC1 after. The same view once the live sync landed: "Synced just now", today 565M. |
| `03-overview-usage-7d.png` | AC2. 7D: "5.61B tokens in the last 7 days" with no change claimed (Codex is recorded only from 20 Oct, inside the earlier week); trend at a third of the window; "Agents in the last 7 days" tiles; one quiet line for the four agents with no usage. |
| `04-overview-usage-30d.png` | AC2. 30D: "37.91B tokens in the last 30 days" and no change claimed. The run before `007d43c` read "▲ 2175.9%" here because Claude Code's logs start on 23 Sep. |
| `05-overview-cost-7d.png` | Addendum 2, fix round 1, merged build. "$189.79 / API estimate for today at public rates"; "$1,982.64 in the last 7 days" with no change claimed (Codex is not fully priced on every compared day); tiles "$1,783.06", "$199.59 / some tokens unpriced", Cursor "— / no price data"; "Per-model breakdown in Value →". No day lacks a breakdown in this data, so the chart has no break. |
| `06-overview-cost-30d.png` | Addendum 2, fix round 1, merged build. "$13,217.44 in the last 30 days": with WP-1's 92-day model history the whole range is priced, so there is no "priced from" note and no unknown day; GitHub Copilot is now priced ($0.04, WP-1 pricing). |
| `07-overview-quota.png` | AC3 and AC4. Hero "36% / Claude Code · default, weekly window — the tightest live quota" with its pace and "Lasts to reset"; one row per live quota with the same forecast; Antigravity "No reading from the last sync · Details →"; "No live quota source, local logs only: Cline, opencode, GitHub Copilot". The Claude row reads 8%: it is the account with the most room (see the drill-in), not the tightest. |
| `08-claude-drillin-top.png` | AC4, AC6 and addendum 3. "Back", "Local logs", "Watches ~/.claude/projects"; numbers with captions under them ("473M / Tokens today"); "Quota windows" with the pace sentence wrapping, never cut; "Extra usage $21.52 of $50.00 · off, out of credits" (Debug fixture). |
| `09-claude-drillin-scrolled.png` | AC5 and addendum 1. Scrolled past quota: accounts, today's token split and "Value by model, this month" in one column, no empty column; "claude-haiku-4-5-20251001 fast" shows a tier key as the model plus the word "fast" (Debug fixture re-keys the month's least-used model). |
| `10-value.png` | AC6 and addendum 3. "Plan value this month", "18.5× Goblin mode" (a word, no badge box), "Claude Code extra usage" with the Debug fixture, and the excluded-from-total note in the body font. Taken 5 s after a launch, so it shows the saved numbers ("Saved 2 min ago · updating…"). |
| `11-settings.png` | AC7 and addendum 3. Sentence-case headings: Monthly plan cost ("$ 400.00 /mo" with a symbol-only presets pull-down), Live quota switches, Quota alerts (threshold switch, warn-before-run-out, per-agent thresholds "80, 95"). Startup sits below the fold. Gemini's switch appears only once Gemini is added as an agent, and it is not added on this Mac. |
| `12-menubar-popover.png` | AC3 and AC4. The popover content in a Debug stand-in window: "567M / tokens today · incl. cache", "Plan value 18.5× Goblin mode", "Tightest quota 36% / Claude Code · default · weekly window / 55 pts of room · Lasts to reset". The focus ring on "Tokens" is unverified in the real menu-bar popover. |
| `menu-selftest.txt` | AC8. `SELFTEST PASS`, 12 checks: every View and Go shortcut is a menu item with its key; ⌘2, ⌘3, ⌘1, ⌘[ and Esc move the window; Back is disabled on a tab and enabled in a drill-in. |
