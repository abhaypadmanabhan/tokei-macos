# WP-W round 2c: match the page to the real app and CLI (orchestrator)
The app UI and CLI are now built. Make the site's rebuilt UI and strings match them; keep everything that already passes.
Sources (read only):
- Real app captures: ~/Library/Developer/TokeiWork/proof/burn-ui/captures/dropdown-sample-{dark,light}.png (menu bar
  dropdown with the burn strip: ring, "1.5× of today's goal", "$14.62 on your plans today", flame + "11-day streak  goal
  hit today", hourglass + "Codex 5-hour · 62% left · 42 min"), captures-real/real-burn-*.png (Burn tab: Overview/Burn/
  Value/Agents tabs, big $ "burned on your plans today, of a $X goal", "Share my week", "Use it or lose it", "This week's
  agents", "Records", "Left on the table"), captures/share-card.png, captures/settings-burn-nudges-*.png. Some files in
  captures/ are blank (old runs); ignore blanks. The worker may refresh them; use what is there now.
- CLI and Settings strings on dev: /Users/abhayp/src/tokei-macos/AIUsageDashboard/TokeiCLI/StatusFormatting.swift
  (BurnFormatting: `tokei burn` output), TokeiCLI/AgentCommands.swift + Core/Connect/AgentConnection.swift (exact
  `tokei mcp install` output lines), UI/Settings/AgentConnectSection.swift (Connect agents row copy), and README.md
  "Agents" section. Use real output lines verbatim in the terminal scene (no invented flags).
Do:
1. Burn strip, Burn section and badges: same wording, order and glyphs as the app (flame for streak, hourglass for the
   expiring line); badge visuals follow the app if it differs from plain rings. Numbers can stay sample values.
2. Terminal scene: real `tokei mcp install --client codex` and `tokei burn` output per the source above.
3. Settings "Connect agents" scene: the real row labels/states/buttons.
4. Mention "Share my week" only as the app does it (a card you can copy or save).
5. Remove other unused dependencies (gsap, @gsap/react, shaders, @base-ui/react, lucide-react, clsx, tailwind-merge,
   class-variance-authority, tw-animate-css) ONLY if nothing imports them (build, CSS and components/ui included); one
   commit; audit before/after.
Then: clean build with every gate, test:gates, headless proof 1440 + 390 (console errors 0) incl. a side-by-side
`proof/site/round2c/compare-dropdown.png` (site scene vs app capture), append "Round 2c" to W-site.result.md, keep
STATUS: READY if all pass, print TOKEI_W_DONE.
