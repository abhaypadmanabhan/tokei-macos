# 09 · Multiple accounts on one Mac

How Tokei finds more than one Claude Code account, what it tells you when it does,
and — the part no detector can solve — what to do when two accounts are hiding
inside one directory.

Written for the person using the app. `06-provider-spec.md` has the model shapes;
the README's *Multiple Claude Code accounts* section has the credential and
aggregation detail.

## 1. The short version

- Discovery is **automatic**. You do not configure anything.
- Tokei finds every Claude config directory, asks each **which Anthropic account it
  is signed into**, and groups directories that answer with the same account into
  one. So several directories can be a single account — see §3.
- It can only see an account that **has** a directory. A directory reports the one
  account it is currently signed into, and that is the whole limitation.
- If it finds more than one, it says so once, on the Overview, and puts each
  account's own usage under **Accounts** in the Claude Code view.
- If you have two Anthropic logins but use them **one at a time out of the same
  directory**, Tokei cannot see the second one. Nothing on disk distinguishes
  them. Section 4 is how you fix that.

## 2. What Tokei can and cannot see

Claude Code keeps everything about an account — session logs, settings, the
signed-in identity — under one config directory. `~/.claude` by default, or
whatever `CLAUDE_CONFIG_DIR` points at.

**Can see**

| Situation | Result |
|---|---|
| `~/.claude` and `~/.claude-work`, each signed into a different account | Two accounts |
| Two directories signed into the **same** Anthropic account | **One** account, both directories listed on its row |
| A `.claude-*` directory with no `projects/` folder | Not an account — it has never run a session |
| A directory that exists but cannot be read this refresh | Flagged by name on the account's row, so you know the total is short |

**Cannot see**

| Situation | Result |
|---|---|
| Two logins taking turns in one `~/.claude` (`/logout`, sign in as someone else) | **One** account. Their usage is added together and cannot be separated |

That last row is not a bug to be fixed later. Logging out and back in leaves no
per-identity trace on disk, so there is nothing for Tokei to read. The only route
is to give each account its own directory — section 4.

## 3. How discovery works

On every refresh, Tokei looks in your home directory for:

- `~/.claude`, the default, and
- any sibling `~/.claude-*` directory that actually contains a `projects/`
  folder.

The `projects/` requirement is what separates a real account from unrelated
dotfiles — `~/.claude-worktrees` is a scratch area, not an account, and is not
counted as one.

Each directory is then asked **which Anthropic account it is signed into**
(`oauthAccount.accountUuid`, read from that directory's config file — for the
default account that file lives beside the directory at `~/.claude.json`, for
every other one it lives inside at `<dir>/.claude.json`). Directories that answer
with the same identity are folded into **one** account, and its row lists every
directory it owns, one per line. So three directories can legitimately show as
two accounts, and the row tells you which two are the same person.

A directory whose identity cannot be read — never signed in, config missing or
malformed — always stands alone. Tokei would rather list one person twice than
merge two people into one row.

## 4. Splitting two logins into two accounts

Do this once per extra account.

1. Pick a directory name that starts with `.claude-`. The prefix is what makes
   Tokei find it. Anything after it becomes the account's label in the app, so
   name it something you will recognise:

   ```bash
   # ~/.claude-work → labelled "work"
   # ~/.claude-personal → labelled "personal"
   ```

2. Start Claude Code pointed at it, and sign in with the account you want to keep
   there:

   ```bash
   CLAUDE_CONFIG_DIR=~/.claude-work claude
   ```

   Claude Code creates the directory, and the sign-in writes the identity and the
   session logs into it.

3. Make it stick for that context, so you do not have to remember the prefix.
   Either export it per shell:

   ```bash
   # in a project directory, a work shell, or a tmux session
   export CLAUDE_CONFIG_DIR=~/.claude-work
   claude
   ```

   …or alias it:

   ```bash
   # ~/.zshrc
   alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'
   ```

   With `CLAUDE_CONFIG_DIR` unset, Claude Code uses `~/.claude` — so your original
   account keeps working exactly as it did, with no changes.

4. Run at least one session in the new directory. Until `projects/` has something
   in it, there is nothing to count and Tokei will not list it.

5. Back in Tokei, refresh. The new account appears under **Accounts** in the
   Claude Code view.

Nothing needs to be moved or copied. Usage already recorded in `~/.claude` stays
attributed to `~/.claude` — Tokei reads history, it does not rewrite it, so
splitting accounts today does not retroactively split yesterday.

## 5. Reading the numbers once you have several accounts

Two different rules sit on the same page, on purpose, and the app names both on
screen:

- **Token counts are a sum.** `TOKENS · TODAY` and the daily history add every
  account together.
- **The quota gauge is one account's** — whichever has the **most headroom** right
  now. It is not an average. You can send work to whichever account you like, so
  the capacity available to you is the best account's, not a blend of accounts
  that do not individually exist.

Under **Accounts** you get, per account: its own usage over time on a shared
scale, its total over that same window, its share, its **own** quota, and the
config directories folded into it. The account row's total covers the chart's
window; the tiles at the top of the page are today. Both are labelled.

## 6. Being told this exists

- **More than one account found** → a one-time notice on the Overview naming the
  count and pointing at the Claude Code view. Dismiss it and it stays dismissed
  (`tokei.notice.multiAccount.discovered.v1`). It only appears for a provider you
  still have on your canvas — if you removed Claude Code from the Agents tab,
  Tokei does not reintroduce it through a notice.
- **One account found, in the Claude Code view** → a one-time notice where the
  Accounts section would be, explaining that a directory can only report the one
  account it is signed into, and giving the `CLAUDE_CONFIG_DIR` line from section
  4. Dismiss it and it stays dismissed
  (`tokei.notice.multiAccount.claudeSetup.v1`).

There is no launch modal and neither notice returns. To see one again, clear its
key:

```bash
defaults delete ai.padzy.tokei tokei.notice.multiAccount.discovered.v1
```

## 7. Troubleshooting

**A directory I created is not showing up.** It needs a `projects/` folder with a
real session in it, and its name must start with `.claude-` and sit directly in
your home directory. Run one session in it, then refresh.

**Three directories, two rows.** Two of them are signed into the same Anthropic
account, so they are one account. Both paths are printed on that account's row.

**A row says a directory "couldn't be read on this refresh".** Tokei could see
the directory but not its logs — usually permissions. The totals on that row are
short by whatever is in it. `ls ~/.claude-work/projects` will usually say why.
A directory that simply has no `projects/` folder is *not* reported this way;
absent is not broken.

**An account shows usage but no live quota.** Each config directory has its own
Keychain item. If that account's token has expired, Tokei reports it rather than
refreshing it — refreshing would race the Claude CLI's own token rotation. Run
`CLAUDE_CONFIG_DIR=~/.claude-work claude` once to let the CLI rotate it.

**I want the two accounts merged back into one number.** They already are, at the
top of the page — that is the sum. The per-account split is only in the Accounts
section and in `tokei status --json`.

## 8. For agents and scripts

`tokei status --json` and the MCP `get_usage` tool expose an `accounts[]` array on
each provider:

```jsonc
"accounts": [
  { "id": "/Users/me/.claude",      "label": "default", "tokensToday": 101073707,
    "windows": [ { "type": "weekly", "usedPercent": 21, "confidence": "official", … } ] },
  { "id": "/Users/me/.claude-work", "label": "work",    "tokensToday": 44405877,
    "windows": [] }
]
```

`accounts[].id` is the config directory path — which is exactly what you set
`CLAUDE_CONFIG_DIR` to in order to send work to that account:

```bash
CLAUDE_CONFIG_DIR=/Users/me/.claude-work claude
```

There is no precomputed "which account has the most headroom" field; an account's
utilization is the highest `usedPercent` among its `windows`, and an account with
`"windows": []` reported nothing — which is absence of data, not 0%. Treat it as
unknown, never as free.

See `08-agent-snapshot-schema.md` for the full shape.
