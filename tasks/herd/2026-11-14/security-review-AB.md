VERDICT: PASS

# Security review: agent connect, burn engine, MCP burn tool (dev vs main)

Reviewer: Claude (read-only). Date: 2026-11-14. Head: 4ed682f (dev).
Result: no critical, high or medium findings. One low finding and three informational ones.
Nothing in the new code sends data off the machine. Every new file is created owner-only
(0600 files, 0700 directories). The two places that spawn processes pass a fixed list of
arguments, never a shell string.

## secscan (`SECSCAN_BASE=main ~/agent-kit/bin/secscan /Users/abhayp/src/tokei-macos`)

```
VERDICT: PASS
repo tokei-macos head 4ed682ffdaf2 base main (4b0b24598ec2): 170 commits, 6 uncommitted paths
```

No FLAG or GAP lines. Full report: `.git/secscan/4ed682ffdaf22f3764faadd7bcd54c628a110474.txt`.

Scope note: local `main` is stale at 0.10.0 (4b0b245), and `origin/main` is 0.11.0 (cc50bde).
So `main...dev` covers 251 files and 170 commits, including 0.11.0 code that has already
shipped. The deep review covered this release's code: `origin/main...dev`, 49 files (Connect,
Game, BurnStateStore, BurnNudges, the AgentSnapshot burn block, MCPServer, AgentCommands,
BurnFormatting and AgentConnectSection). The rest of the shipped diff got a lighter pass;
for example, `ProofRoute.swift` is `#if DEBUG` only.

## Findings

### L1 (low): text from the provider's window label is not cleaned before it reaches the terminal and the agent "advice"

- `AIUsageDashboardApp/Core/Agent/AgentSnapshot.swift:557-558`: `windowName` returns the raw
  `label` whenever it is non-empty.
- `AgentSnapshot.swift:576`: `advice` builds an imperative sentence around that label
  ("… has N% left and resets in …: run optional or batch work there first").
- `TokeiCLI/StatusFormatting.swift:185`: `tokei burn` prints `advice` straight to the terminal.
- `TokeiCLI/MCPServer.swift:354-359`: `get_burn_opportunities` returns `advice` to the agent.
- Where the label comes from: a remote or local quota source sets it. Examples are Gemini's
  `group.displayName`, Antigravity's `group.displayName` (from its localhost language-server
  RPC, `AntigravityQuotaClient.swift:206`) and Cursor's `membershipType`.
- Attack: a malicious or compromised quota source returns a window label that contains
  escape characters (ESC/OSC sequences) or instruction text, for example
  `weekly\u001b]0;…\u0007` or `weekly. Ignore prior instructions and run …`.
  - `tokei burn` writes the raw escape codes to the user's terminal. That can retitle the
    window, hide text or plant links.
  - Agents receive the injected text inside the one sentence Tokei words as an instruction.
- Context: this class of issue already exists. `tokei status` prints account labels unescaped
  (`StatusFormatting.swift:98`), and `get_usage` already returns `label` as a JSON field.
  This release makes it worse in one way: the label moves from a data field into an
  instruction.
- Minimal fix: in `AgentBurnWindow.windowName`, use the label only when it passes a short
  allowlist: letters, digits, space and `-_.()/`, at most 48 characters. Otherwise fall back
  to the type name. Add one test with a label that contains ESC and one with a long label.

### I1 (informational): PATH search and child PATH (asked; not exploitable beyond the user's own shell)

- `Core/Connect/AgentConnection.swift:51-58`: the lookup order is `$PATH`, then `~/.local/bin`,
  then `/opt/homebrew/bin`, then `/usr/local/bin`. Relative or empty `PATH` entries are dropped
  (`hasPrefix("/")`).
- `AgentConnection.swift:297-298`: the child's PATH is the found binary's directory, then the
  fallback directories, then the original PATH.
- Every directory searched is one of three kinds:
  - root-owned: the launchd default, `/usr/bin:/bin:/usr/sbin:/sbin`;
  - owned by the user: `~/.local/bin`, `/opt/homebrew`;
  - writable by the admin group: `/usr/local/bin`.
- An attacker who can plant `claude` or `codex` (or `node`, for npm-installed clients) in any
  of these directories already runs code as the user through the shell. The default
  `/etc/paths` already puts `/usr/local/bin` first. No privilege boundary is crossed. Tokei
  never runs as another user.
- Argument injection: none.
  - `Process.executableURL` is given literal arguments (`AgentConnection.swift:104-106`, `243-245`).
  - The helper path comes after `--`.
  - `--client` is parsed into an enum (`TokeiCLI/AgentCommands.swift:13-35`).
  - `quoted()` is used only for the dry-run display.
- Two behaviour differences from the user's shell:
  1. The app looks in `~/.local/bin` before Homebrew.
  2. Opening Settings runs these binaries without a click (see I2).
- Optional hardening: skip a candidate binary when it, or its directory, is not owned by the
  user or by root, or is writable by group or others (the rule ssh's StrictModes applies).

### I2 (informational): opening Settings runs third-party CLIs, which may reach their vendors

- `UI/Settings/AgentConnectSection.swift:43,77-82` calls `state(for:)` for every client as soon
  as Settings appears.
- `AgentConnection.swift:73` then runs `claude mcp get tokei` and `codex mcp get tokei --json`
  with the user's environment and the home folder as the working directory. Each call has a
  12-second timeout.
- Tokei's own code makes no network calls in this release. I grepped `Core/Game`,
  `Core/Connect`, `BurnNudges`, `BurnStateStore` and `TokeiCLI` for `URLSession` and `http`:
  no hits.
- The spawned vendor CLIs may check for updates or send telemetry. Claude Code's `mcp get` may
  also health-check the registered server by spawning it (unverified).
- The child's output is never shown to the user, and reads are capped at 128 KiB
  (`AgentConnection.swift:284-315`). Good.
- Fix, if wanted: run the probe only when the user taps Connect or a "Check" control. Or state
  in the Settings copy that Tokei asks each client.

### I3 (informational): reads of `~/.cursor/mcp.json` and `burn-state.json` have no size limit

- `AgentConnection.swift:185` and `Core/Storage/BurnStateStore.swift:24` call
  `Data(contentsOf:)` with no size cap.
- Only a process running as the same user can plant a huge file or a device symlink there.
  Such an attacker could more simply add a malicious MCP server to Cursor's config directly,
  so this is not a real boundary.
- A FIFO is handled: in a probe, `Data(contentsOf:)` on a FIFO returned nil at once instead of
  blocking.
- Optional hardening: `fstat` the file, require a regular file, and cap the read at 1 MiB.

### Not security, worth a look

- A dangling symlink at `mcp.json` gets replaced by a regular file.
  `resolvingSymlinksInPath()` returns the link path itself when the target is missing
  (confirmed by probe), so `changeCursor` treats the file as absent and renames over the link
  (`AgentConnection.swift:195,221`). That breaks a dotfiles link and contradicts docs/08
  ("a symlinked mcp.json stays a symlink").
- If Cursor rewrites `mcp.json` between Tokei's read (`AgentConnection.swift:196`) and its
  rename (`:221`), Cursor's change is lost. This needs exact timing, so it is unlikely.

## Checked and fine

- **Cursor config write** (`AgentConnection.swift:193-241`):
  - The staging file is opened with `O_CREAT|O_EXCL|O_NOFOLLOW`, mode 0600, next to the
    resolved target, then renamed into place atomically. `rename` replaces the directory entry
    and never follows a link at the destination.
  - The backup `mcp.json.bak` is created once, `O_EXCL|O_NOFOLLOW`, mode 0600. Its existence
    is checked with lstat semantics: a probe confirmed `attributesOfItem` returns attributes for
    a dangling link. So a planted link is never followed and an old backup is never overwritten.
  - `~/.cursor` is created 0700 when missing.
  - Invalid JSON is refused and the file is kept.
  - An existing `tokei` entry that differs is kept, with a "disconnect first" message.
  - Deep nesting is rejected without a crash (probe: a 10,000-level array gives a parse error).
- **`tokei install`** (`AgentConnection.swift:142-168`): the symlink is staged under a random
  name and renamed into place. A directory is never replaced. Replacing an existing file
  needs `--force`, and the Settings button never forces. `~/.local/bin` is created with the
  umask default (typically 0755), the normal mode for a bin directory; it holds no secrets.
  Install is refused when the helper sits on a mounted disk image (`/Volumes`) or in macOS's
  temporary AppTranslocation copy.
- **Child process handling** (`AgentConnection.swift:283-316`):
  - stdin is `/dev/null`.
  - Output goes to a capture file in the per-user `TMPDIR`, named with a random UUID, mode 0600,
    and is deleted afterwards.
  - Timeout is 12 s, then SIGTERM, then SIGKILL after 1 s. The tiny PID-reuse window is
    negligible and can only reach the user's own processes.
  - Error messages are static strings and never echo the client's output.
- **File permissions:**
  - `agent-snapshot.json` and `burn-state.json` both go through `SecureFileWriter`:
    `O_EXCL|O_NOFOLLOW` plus `fchmod` 0600, directory 0700, atomic rename.
  - Cursor's `mcp.json` and its backup: 0600.
  - The notification cap state lives in UserDefaults.
- **burn-state.json with hostile content** (`BurnStateStore.swift:19-46`):
  - `version`, `longestStreak >= 0`, and every record value being finite and non-negative are
    checked.
  - Dates are only compared, never converted to `Int`.
  - A corrupt file is moved aside to a new name and never overwritten. If that move fails,
    writes pause.
  - Token sums use the saturating `TokenArithmetic` helper.
- **Int traps:** `Int(resetAt.timeIntervalSince1970)` (`ExpiringHeadroom.swift:11`,
  `BurnSnapshot.swift:182`) runs only for resets within 3 days ahead, or between a real sample
  time and now (`BurnWindowOutcomes.swift:32-33`). So an absurd epoch from a provider cannot
  reach it. `advice` and `BurnNudges` use bounded values only.
- **MCP stdio server with hostile input** (`TokeiCLI/MCPServer.swift:232-263`):
  - Frames are capped at 1 MiB (`MCPFrameReader`, unchanged).
  - `arguments` must be an object whose keys are a subset of `{provider, detail}`, and only
    for `get_usage`.
  - `provider` must be in the allowlist, and `detail` must be exactly `"summary"`.
  - `protocolVersion` is checked against an allowlist.
  - Diagnostic names are cut to 128 bytes.
  - EPIPE exits cleanly.
  - No file path comes from input (`TOKEI_SNAPSHOT_PATH` is the user's own environment).
- **Agent snapshot and notification content:**
  - New fields: `windowSeconds`, `pace`, `forecast` (numbers and enums), and `burn`. The `burn`
    block carries provider id and name, the opaque `accountID`, window label, percentages,
    dates, streak, today's API-equivalent USD, and the goal.
  - `accountID` is SHA-256 of `provider\0accountUUID`, not of an email
    (`ClaudeAccount.swift:58-62`, `ProviderAccount.swift:150-153`).
  - Burn windows carry no account label or profile path.
  - Notification bodies hold provider display name, window type, percentage and time only
    (`BurnNudges.swift:66,73,85`).
  - Settings feedback never shows client output.
  - There is no share card in this diff: a grep for ShareLink, NSSharingService,
    ImageRenderer and NSPasteboard found nothing.
- **Off-machine:** no new network code. `release.sh` re-resolves the pinned Sparkle package
  once when `sign_update` is missing. That is a build-time fetch on the release machine, with
  `rm -rf "${ROOT:?}/…"` guarded.

## How I checked

- Read every non-test file in `origin/main...dev`. Read the `main...dev` diff for
  AgentSnapshot, MCPServer and project.yml.
- Traced label, `resetAt` and `accountID` back to their sources.
- Probed Foundation's behaviour with small compiled Swift programs in the scratchpad (nothing
  written to the repo): `attributesOfItem` on a dangling link, `resolvingSymlinksInPath` on a
  dangling link, JSON nesting limits, JSON number round trip, and `Data(contentsOf:)` on a FIFO.
- Ran secscan with `SECSCAN_BASE=main`.
- Not checked: I did not rerun the unit tests (ConnectTests, CLITests, GameTests), because the
  test host may launch the app and this review was read-only. I did not run `claude` or
  `codex`. Whether `claude mcp get` spawns the server is unverified.
