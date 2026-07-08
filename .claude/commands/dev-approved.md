---
description: Promote verified dev work toward release — open/refresh the dev→main PR, run Greptile + /security-review + /simplify, apply release gates, prepare & verify the macOS archive, update release docs and website, without merging to main unless told.
argument-hint: "[optional: version bump, e.g. 0.1.1 or 'minor']"
allowed-tools: Bash(git*), Bash(gh*), Bash(bash .claude/gates/*), Bash(xcodegen*), Bash(xcodebuild*), Bash(codesign*), Bash(xcrun*), Bash(spctl*), Bash(ls*), Bash(find*), Read, Write, Edit, Skill
---

# /dev-approved — promote dev toward release

Manual testing passed. Prepare a shippable release candidate. **Do NOT merge to `main`**
unless the user explicitly instructs it or repo policy allows. Optional version arg: `$ARGUMENTS`.

Announce: "Using /dev-approved to prepare the release candidate."

## Step 1 — Confirm dev is clean & fully tested

```bash
git checkout dev
EXPECT_CLEAN=1 bash .claude/gates/preflight.sh
BASE_REF=main bash .claude/gates/run-all.sh full
```
Abort if anything is red — a failing gate here means dev is not release-ready; send the
user back to `/agents-done` or `/dev-reject`.

## Step 2 — PR dev → main

If `gh` is authenticated:
```bash
gh pr view dev --json url,state 2>/dev/null || \
gh pr create --base main --head dev --title "Release candidate: dev → main (<version>)" \
  --body-file tasks/patch-bibles/<date>.md
```
Otherwise create `tasks/reports/release-<date>.md` as the PR body and tell the user to
open the PR manually. Report PR URL/state either way.

## Step 3 — Greptile review

If a Greptile app/integration is configured on the repo, request/inspect its review and
summarize findings. If not available, say so and rely on `/security-review` + `/code-review`.

## Step 4 — Security review

Run `/security-review` on the `main...dev` diff. Triage every finding: fix in a focused
commit on `dev`, or record an explicit accepted-risk note in the release doc. **Never skip
this before release.**

## Step 5 — Simplify

Run `/simplify` where the merged patches are overcomplicated (quality only — not a bug
hunt). Apply safe simplifications on `dev`, re-run `build` + `test` after.

## Step 6 — Release gates (strict)

```bash
BASE_REF=main bash .claude/gates/run-all.sh release   # STRICT_GATES=1: lint/format become hard
```
Plus: dependency audit (no new unvetted deps in `project.yml`), release notes present,
no secrets (`no-secret` with `BASE_REF=main`), version bumped in `AIUsageDashboard/project.yml`
`MARKETING_VERSION` if `$ARGUMENTS` requests it.

## Step 7 — macOS release archive (if releasing a build)

```bash
cd AIUsageDashboard && xcodegen generate
xcodebuild -project AIUsageDashboard.xcodeproj -scheme AIUsageDashboardApp \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/Tokei.xcarchive archive
```
Then, only if signing/notarization is configured (a real `DEVELOPMENT_TEAM` / Developer ID
in `project.yml` — currently it is `""` / adhoc `CODE_SIGN_IDENTITY: "-"`):
- export with an export options plist, `xcrun notarytool submit … --wait`, `xcrun stapler staple`,
- verify: `codesign --verify --deep --strict --verbose=2 <app>` and `spctl -a -vvv <app>`.

If signing is NOT configured, STOP before notarization and report: "adhoc/unsigned —
notarization skipped; configure DEVELOPMENT_TEAM + Developer ID to notarize." Document the
adhoc archive as a test artifact, not a distributable. Record every produced artifact + path.

## Step 8 — Release documentation

Update (create if missing): CHANGELOG / release notes, known issues, "manual QA completed"
record (link the `/agents-done` checklist run), rollback instructions (`git revert -m 1 <merge-sha>`
per package; `dev`/`main` safety net). Keep the Patch Bible linked as the audit trail.

## Step 9 — Website

If a product website exists in/near the repo, update the release/product copy (version,
new-provider support, changelog highlight). If NO website exists, create
`tasks/reports/website-todo-<date>.md` listing exactly what to update when one exists
(version, supported providers, feature highlights, download link).

## Step 10 — Do not merge to main

Leave the PR open for the user's final approval unless they explicitly said to merge (or
repo policy allows auto-merge). If instructed to merge: `git checkout main && git merge --no-ff dev`,
tag `v<version>`, and report — but never on your own initiative.

## Output

1. PR link/status. 2. Greptile review status. 3. Security-review status + triage.
4. Simplify findings applied. 5. Release checklist (gates, deps, notes, version).
6. Notarization/signing status. 7. Release docs updated (paths). 8. Website update/TODO.
9. Remaining manual steps before shipping.
