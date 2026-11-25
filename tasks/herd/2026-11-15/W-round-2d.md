# WP-W round 2d: the release flip (0.13.0 is merged to main; the notarized DMG is being built now)

1. `routeCli.output`: regenerate from the final signed helper
   `~/src/tokei-macos/AIUsageDashboard/dist/Tokei.app/Contents/Helpers/tokei` (reports `tokei 0.13.0`; its route
   text was polished since round 2b: window names in words, "42 min" style countdowns, plain pace words) through
   `scripts/cli-sample.mjs`. Verbatim lines only. The demo's reason sentences should match what this build prints.
2. Flip the three claims to shipped (`route`, `routeCli`, `footprint`) and swap the hero and route section to the
   0.13.0 captures. Footprint figures stay the median-of-three from `A-speed.result.md` (0.478%, 1.583% before,
   66.9 MB); the final signed build measured 0.481% and 65.1 MB in one run, which agrees.
3. `lib/site.ts`: version 0.13.0, the download URL in the same pattern as 0.12.0
   (`…/releases/download/v0.13.0/Tokei-0.13.0-arm64.dmg`), and the download size from the real file
   `~/src/tokei-macos/AIUsageDashboard/dist/Tokei-0.13.0-arm64.dmg` once it exists (it appears when notarization
   finishes, within about 15 minutes; wait for it with a bounded loop, do not guess the size).
4. Copy: the agents chapter says the same thing twice ("Agents get the same ranked list … The same answers come
   from the tokei command"); make it one clear sentence. Read the whole page once more against
   `product-design`'s `references/copy-and-slop.md` and fix anything that reads like filler.
5. Rebuild with all gates, `corepack pnpm test:gates`, page-check at 390 and 1440, full-page screenshots into
   `shots-r2d/`, servers stopped. Commit. No deploy, no push.
Append "Round 2d" to your result, then
`echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-fix-r2d.done` and run
`hc send t1d "W round 2d done"`.
