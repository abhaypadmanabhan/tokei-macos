# How amazing websites are made — research + a story-driven plan for Tokei

Research pass for the Awwwards-tier rebuild. Sources: first-hand teardown of
`experientiallabs.ai` + `mireye.com`, plus 4 focused research briefings (GSAP/scroll,
WebGL/shader, nav patterns, build process). Everything below is implementation-level.

---

## 1. What the reference sites actually are (teardown)

**experientiallabs.ai** — Next.js. One full-screen hero, no long scroll. The craft is
*restraint*:
- A single **canvas** drawing concentric orbital rings with small nodes slowly orbiting
  (hypnotic ambient motion, not flashy).
- **Serif italic display** headline ("Your AI 90% cheaper…") paired with **mono** UI
  labels (`EXPERIENTIAL LABS`, `RESEARCH ↗`, `BACKED BY Y COMBINATOR`, `100 stars`).
- Corner-anchored mono labels frame the composition (top-left brand, top-right nav,
  bottom-left credit, bottom-right stat). Massive negative space. One dark CTA.
- Lesson: **type pairing + one ambient canvas + editorial framing** reads as premium
  with almost nothing on screen.

**mireye.com** — Framer site (Framer Motion, SVG-driven, no canvas), served on Vercel.
- **Floating glass pill nav**: `position:fixed; top:1rem; border-radius:100vw;
  backdrop-filter:blur; ` centered — logo left, links center, `Docs` pill + solid
  `Sign up` right.
- Hero visual is an **ASCII / dot-matrix globe** (terminal texture as hero art) behind a
  big sans display headline; **accent color on the key words** ("Real World", "make
  decisions") — not the whole line.
- Dev-tool CTAs: `Compare →`, `Read the docs ↗`, `Copy Skill ⧉` (copy-to-clipboard).
- Cards with **bordered mono tag chips** (`Slope` `Flood` `Surface water` `Soil`).
- Lesson: a **terminal/ASCII motif** + **floating pill nav** + **accented keywords** is
  exactly the register a dev tool wants.

Both: near-monochrome, one accent, mono details, oversized display type, heavy whitespace.
**This is already Tokei's DNA** — we push motion + narrative, not decoration.

---

## 2. The stack that builds these (and what each layer does)

| Layer | Tool | Job |
|---|---|---|
| Framework | Next.js (App Router) — already ours | routing, RSC, static hero |
| Smooth scroll | **Lenis** `lerp 0.08–0.10`, desktop-only | the #1 "expensive" tell; wire to GSAP ticker |
| Scroll motion | **GSAP + ScrollTrigger** (+ SplitText, DrawSVG, Flip) | pinned narrative "acts", scrubbed scenes, text reveals |
| Component motion | **Framer Motion** (optional) | `layoutId` morphs (pill→command palette), tab crossfades |
| Ambient visual | **CSS mesh-gradient** or **OGL** (8KB) — one touch max | dim accent aurora / one hover effect, never both |
| Texture | SVG `feTurbulence` / PNG grain, `mix-blend-mode:overlay`, ≤0.05 | kills banding on dark flats, "print" feel |
| Native | CSS `animation-timeline: view()/scroll()` | compositor-cheap entrance reveals for the long tail |

We already ship Lenis + GSAP + SplitText. **We're one narrative pass and a texture pass
away** — not a rewrite.

---

## 3. Technique catalog (the ones that fit a dark editorial dev tool)

Ordered by impact-to-risk. `T/O/CP` = animate transform/opacity/clip-path only.

1. **Lenis, desktop-only** (`lerp 0.09`), disabled on touch via `matchMedia`. Biggest
   single premium tell.
2. **SplitText line-mask reveals** on every section heading — `mask:true`, short travel
   (`yPercent:110`), tight stagger. Editorial, not flashy. (We do this already; extend it.)
3. **One pinned hero act** — the Tokei app window *assembles itself* on a scrubbed
   timeline (chrome → number counts → chart draws → agents populate). Used ONCE. The
   anchor moment.
4. **Line-draw SVG** (DrawSVG / `stroke-dashoffset`) — connective diagrams, the chart, a
   "flow from your agents → Tokei" schematic. Reads as *systems/data* without color.
5. **Tabular-nums counter ticks** — every metric ticks up on enter (`snap:{textContent:1}`).
   Mono makes digits land without width jitter.
6. **Clip-path wipe** on code/terminal panels and before/after — sharp, geometric,
   on-brand for dev tools.
7. **Sticky stacking feature cards** (CSS `position:sticky` + subtle scrub `scale`) —
   depth without a 3D scene.
8. **Native CSS `view()` fade/rise** for secondary blocks — keeps the GSAP budget for the
   hero act.
9. **Magnetic CTA + rolling-text nav links** (two-row `overflow:hidden` swap, per-char
   delay) — micro-craft on the elements users touch.
10. **Dim accent aurora** (CSS or one OGL pass) — a single faint `#FF3B70` bloom from a
    corner, `speed ≤0.15`. Plus grain everywhere. That's the whole "gradient" budget.

**Discipline line (what separates Awwwards from slop):** T/O/CP only; `will-change`
scoped to active scenes then removed; everything ambient in CSS; GSAP reserved for the
one or two scrubbed acts; `matchMedia` reduced-motion + LCP-safe hero (headline renders
solid, never gated behind a JS reveal).

**Slop to avoid:** colorful 4-color mesh gradients, real bloom+chromatic-aberration
passes (gamer register), particle fields/metaballs (startup-2021), full three.js for a
background (200KB against a "stay fast" brief), custom cursor everywhere, numbered
`01/02` sections (already killed).

---

## 3b. Motion language (the spec sheet — reuse everywhere)

Award studios ship a *motion doc* so N sections feel like one hand. Ours:

- **Durations:** UI micro 100–150ms · standard UI 150–250ms · **marketing/narrative
  0.6–1.2s** (expressive) · exits ~20% faster than entrances.
- **Easing (arriving / ease-out):** `cubic-bezier(0.19,1,0.22,1)` expo ·
  `cubic-bezier(0.23,1,0.32,1)` quint · `cubic-bezier(0.165,0.84,0.44,1)` quart.
- **Easing (on-screen travel / ease-in-out):** `cubic-bezier(0.77,0,0.175,1)` quart ·
  `cubic-bezier(0.645,0.045,0.355,1)` cubic.
- **Scrubbed scenes:** `scrub: 1`. **Counters/telemetry:** `ease: none` so numbers read
  as *measured, live* — not decorative.
- **Golden rule:** animate `transform`/`opacity`/`clip-path` only; `will-change` scoped
  then removed; `prefers-reduced-motion` fallback on every animation.

**Preloader → hero handoff (signature move):** a mono `%` counter races 0→100 in pink
over black; on complete it *becomes* the hero's live token count. The loader's exit **is**
the hero's entrance — one continuous ~1s move, not two events.

**Type note:** our display is Archivo Black + DM Mono (good, real faces). Body is Inter —
flagged as a slop-default by studios; fine to keep, but a distinctive grotesk or a
genuine mono (JetBrains/Berkeley) for body would raise the register. Low priority.

**Accent discipline:** `#FF3B70` is *scarce* — it's the "live token" pulse. Near-black +
hairlines (`rgba(255,255,255,.08)`) carry everything; pink is spent only on live state,
active tier, the single primary CTA, and released generously **once** at the final act.

## 4. Story-driven Tokei — section-by-section, motion per section

The narrative arc: **tension → proof → mechanism → payoff → trust → act.**
Tokei's story: *"You pay flat rates for AI. Are you winning or losing? Here's the number,
and here's exactly where it comes from."*

**00 · Nav** — floating glass pill (terminal register). Centered wordmark, mono links,
`⌘K`-style download chip with a blinking `#FF3B70` caret. Transparent → blur+hairline on
scroll; hide-on-scroll-down / show-on-up via `quickTo(yPercent)`. Magnetic download.

**01 · Hero (tension)** — the question, huge, LCP-safe. Behind it a **line-draw schematic**:
faint hairlines flowing from 7 agent nodes (Claude Code, Codex, Cursor…) into a single
Tokei node — "many logs → one panel," drawn on load. Dim accent aurora from top-right.
CTA magnetic + `View source`.

**02 · The pinned reveal (proof)** — pin the viewport; as the user scrolls, the **real
Tokei window assembles**: chrome fades in → `548M` counts up → line chart draws →
agent grid populates row by row → tab flips Overview→Value → `3.4×` lands with `MAXXING`.
This is the authenticity centerpiece, now *earned* through motion. One act, scrubbed.

**03 · How it works (mechanism)** — 3–4 **sticky stacking cards**, each a beat:
"tails local logs" (clip-path terminal wipe showing a log line) → "real quota windows"
(countdown ticking) → "prices tokens at API rates" (two numbers resolve: `$245 → $833`) →
"names your number" (the Maxxer ladder lights the active tier). Line-draw connectors.

**04 · Coverage (proof of breadth)** — the 7 agent tiles, each counter ticking, live-quota
vs local-logs labeled. `view()` rise-in stagger.

**05 · Privacy (trust)** — "never leaves your Mac." Big counter stats (7 / 0 / 100%).
A subtle clip-path "nothing sent" visual — a packet that dissolves at the network edge.

**06 · Payoff / Install (act)** — restated value line, one magnetic CTA. No filler badges.

Reduced-motion: every act collapses to final state instantly; hero renders solid.

---

## 5. Image prompts for you to generate (optional, high-leverage)

Only where a real asset beats CSS. Dark, editorial, one accent `#FF3B70` on `#131316`.
All should be transparent-PNG or dark-bg, high-res, no text baked in.

**A — Hero backdrop schematic (nice-to-have; can also be pure SVG):**
> "Ultra-minimal technical schematic on near-black (#131316). Thin hairline (1px, ~8%
> white) right-angle connector lines flowing from seven small circular nodes on the left
> into one node on the right. Faint blueprint grid. A single hot-pink (#FF3B70) accent
> glow bleeding from the top-right corner, very dim. Editorial, Swiss, restrained, lots
> of negative space. No text. 2560×1440."

**B — Grain/noise tile (or I generate via SVG):**
> "Seamless 512×512 monochrome film-grain / fine noise texture, subtle, high-frequency,
> neutral gray on transparent, for a 4% overlay. No pattern seams."

**C — App-icon / brand hero render (if you want a signature object):**
> "A single matte-black rounded-square app icon floating in near-black space, one hot-pink
> (#FF3B70) fill sweeping across it like a gauge, soft rim light, subtle film grain,
> studio product-render lighting, dramatic shadow, editorial, minimal. Centered, lots of
> negative space. 2000×2000, transparent or #131316 background."

**D — ASCII/dot-matrix motif (mireye-style, if we want a terminal hero texture):**
> "Dense ASCII/dot-matrix art forming an abstract data landscape or globe, monospace
> characters, dim gray on near-black (#131316), one region tinted hot-pink (#FF3B70).
> Terminal aesthetic, high detail, no readable words. 2560×1440."

Tell me which you want and I'll refine the prompt; you generate and hand back.

---

## 6. Proposed implementation (phased, so it stays shippable)

- **Phase 1 — texture + nav** (low risk): grain overlay refine, dim accent aurora, floating
  pill nav with scroll hide/blur + magnetic CTA + `⌘K` caret chip. Rolling-text links.
- **Phase 2 — the pinned hero act**: convert the app-window showpiece into a scrubbed
  assemble-on-scroll timeline (GSAP pin). LCP-safe, reduced-motion collapse.
- **Phase 3 — sticky "how it works" chapters** + line-draw connectors + counter ticks.
- **Phase 4 — polish**: `view()` reveals on the tail, clip-path panel wipes, page-load
  choreography, QA (perf/LCP/reduced-motion/a11y), final build gate.

Each phase ships independently and is verifiable in the browser.
