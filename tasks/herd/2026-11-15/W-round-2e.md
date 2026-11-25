# WP-W round 2e: link previews point at localhost (found on the live page)

The served HTML has `og:url` = `http://localhost:3000` and `og:image` / `twitter:image` =
`http://localhost:3000/opengraph-image.png…`, so a link shared in Slack, X or iMessage gets no preview card.
1. Set the site's canonical origin in one place (`lib/site.ts`, `https://tokei-website.vercel.app`) and use it as
   `metadataBase` (read the Next 16 docs in `node_modules/next/dist/docs/` for the metadata API first).
2. Lock it in: a gate that fails the build when the prerendered HTML contains `localhost` or `127.0.0.1` in any
   `meta` or `link` tag, and requires `og:image` to be an absolute https URL on the canonical origin. Show it red
   on the current code (`~/agent-kit/bin/prove-red`).
3. Refresh `app/opengraph-image.png` and `app/twitter-image.png` (1200x630) to the current hero: the headline
   and the 0.13.0 overview capture, same type and ground as the page. Demo-data capture only.
Rebuild with all gates, `test:gates`, commit, no deploy. Append "Round 2e" to your result, then
`echo "STATUS: READY" > /Users/abhayp/src/tokei-macos/tasks/herd/2026-11-15/W-fix-r2e.done` and run
`hc send t1d "W round 2e done"`.
