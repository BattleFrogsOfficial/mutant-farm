# Handoff — 2026-10-30 (HUD and Almanac after the first Studio pass)

Read `CLAUDE.md` first (rules, conventions, live numbers, commands) and `docs/DESIGN.md` (intent; dated
rule changes at the top). This file is what a fresh session needs on top of them: what changed in the
last session, what has never run in Studio, what is still undecided, and what to do next, in order.

Repo: https://github.com/BattleFrogsOfficial/mutant-farm (branch `main`). Tools: `bash tools/install-tools.sh`.
Place file: `rojo build default.project.json -o MutantFarm.rbxl`.

**The Pumpkin Egg window is open now** (2026-10-29 00:00 EDT to 11-05 23:59 EST). The M5 build it
belongs to has still not been published or played in Studio; see "Next tasks".

## What was done this session

HUD and Almanac fixes from the first Studio pass (10 items). No gameplay or balance change.

| Commit | What |
|---|---|
| `ffd00ac` | Item 1: scale by the shorter edge (1.25x mouse, 1.0x touch); panels fit the canvas; preview sizes + per-area scene/check hooks |
| `a4e75e3` | Items 2-6: top-right tiles + right column, SHOP beside WATER at the plot, WATER label/ring/toast, vector glyphs, egg tray with one next-egg tile |
| `47148bf` | Items 4, 6, 7, 8: "2x" chip on egg timers, live gate income, soil "+" markers, Lab progress in Next Up |
| `9c085c8` | Item 9: Almanac milestone track (markers, labels, tooltips) |
| `6f8e055` | Preview: scene files start from the main UI mount; delayed callbacks run before each capture |
| `ae39fcd` | Review fixes: canvas never under 900 wide, gaps measured as drawn, tray tiles fit their names, touch cap per device, stricter checks |
| `473ee08` | CLAUDE.md UI section, DESIGN.md dated note |
| `17f1867` | Verification fixes: mid-right SHOP/WATER under the column, Cash clear of the top-left chat, 800x600 in the preview |
| `b03a05f` | First version of this handoff |
| (this one) | Review fixes 2: owned names wrap and the next tile reads "SWAMP / AT THE / EGG SHOP" (any two eggs + next fit in 424), Next Up slides clear of mid-right buttons, preview in Montserrat with outlines counted, Almanac/shop spacing; this handoff |

1. **Scaling** (`shared/HudScale.lua`, `Config/Hud.lua`): shorter screen edge (below the top bar) /
   540, capped at 1.25x with a mouse and 1.0x on touch devices (chosen once per device:
   `TouchEnabled and not MouseEnabled`). Two guards on top: the canvas never gets narrower than 900
   (4:3 and docked windows scale by width), and Cash never reaches into Roblox's default top-left
   chat window (only windows under ~900 px wide scale down for it). Panels are content-sized and shrink
   to fit (`Components.panel`). Preview sizes now: 1280x720, 844x390 (screenshots), 667x375, 800x360,
   1024x768, 1920x1080, 1663x726, 960x720, 800x600 (checks).
2. **Top right**: Upgrades / Daily / Almanac tiles 8 px apart *as drawn* (shadow to ink outline; frames
   are spaced gap + 3 px outline + 4 px shadow), red dots inside the tiles. Right column under them,
   8 px apart as drawn: weather chip (always a chip now, quiet navy in the hub), Instant Weather (the
   bundle's width), Starter Bundle, bag (plot).
3. **SHOP size**: biggest in the hub (230x80); at the plot WATER's size (132x64), beside it.
   Mid-right on touch (and at the plot on narrow windows), centered on the canvas height but never
   closer than 8 px under the right column at its tallest in that zone. Where they reach over Next
   Up's row (a 900-1000-wide canvas), Next Up slides left to stay 8 px clear.
4. **WATER**: "WATER" / "· 2x 30s" on two lines, a square drain ring for the 30 s, dimmed (navy) while
   it runs, "2x" chip on every growing egg's timer, a first-use-per-session toast.
5. **Icons**: `UI/Glyphs.lua`, vector glyphs from frames (up arrow, gift, book, coin, gem, egg, bag,
   drop) with ink outline and a hard shadow faded as one CanvasGroup. No ImageLabels for HUD icons.
6. **Egg tray**: owned eggs plus ONE next-egg tile (`ShopRules.nextTrayEgg`, the cheapest unlocked
   Cash egg you have none of: price badge, its name, "AT THE" / "EGG SHOP"); gated tiers never appear.
   Long owned names wrap at their spaces ("STARTER" / "GEM", "🎃" / "PUMPKIN"), so tiles grow only
   with their longest word (estimated in em of Montserrat Black, wide letters and emoji counted),
   badges with their text; tiles are 116 tall for the next tile's three lines. Any two owned eggs
   plus the next tile fit the 424-wide tray without scrolling. Lab's $25K progress: shop carousel +
   Next Up (`shared/NextUp.labGoal`).
7. **Gate sign** second line: `shared/GateSign.incomeText` ("$0/min · plant eggs to earn", then
   "$3.4K/min"); the name line stays.
8. **Soil markers** (`UI/SoilMarker`, `Config/WorldUI`): navy "+" tile on each empty owned patch
   (pulses during the tutorial's plant steps), the next patch's price on the same tile; the old
   server-side price sign is gone.
9. **Almanac track** (`shared/AlmanacTrack`, `Config/AlmanacUI`): title "📖 Almanac N / 410"; the
   current segment (last passed milestone to the next) fills 28% of the bar with a big diamond at its
   end, later milestones smaller and proportional, big ones labeled (🥚 Toxic 100, Void 200, Cosmic
   300, 🍀 +10% luck 400), labels collapse to icons when they'd collide; tap a marker: tooltip.
   Track, tabs, grid and pager sit 8 px apart so no outline touches (cards 110x106).
10. **Preview**: scenes for the tray with 0 / 1 / 2 / 6 eggs (and two-egg trays with a Gem egg, the
    Pumpkin, only Gem eggs), watered, every red dot lit, the glyph sheet, the tallest right column
    over a touch layout (phone and hybrid device), soil / timer / gate (world), Almanac at 5 / 24 /
    26 / 399 and the tooltip. Hooks: `tools/preview/scenes/*.luau` + `tools/preview/checks/*.js`
    (CLAUDE.md, "UI preview"). The preview now renders GothamBlack in **Montserrat Black** (what
    Roblox draws it with since Gotham's removal; `@fontsource/montserrat` in
    `tools/preview/package.json`, so run `npm install` there once), and every overlap check counts
    UIStroke outlines. Sizes add 1000x658 (a 900x540 canvas).

**Verified at the end** (this commit): `lune run tools/check` 124 files, 0 failed ·
`lune run tools/test` 126 passed, 0 failed · `stylua --check src tools tests` clean ·
`node tools/relay/test.mjs` passed · world checker 0 issues with the Halloween decor on (2027 parts;
on by date now) and off (2011 parts, `LIMITED_AT=1800000000`) · UI preview (Montserrat, outlines
counted, 10 sizes): HUD overlap 0 issues across 250 state x size combinations, Shop 0 across 80
scenes, Panel 0 across 30, extra checks (hud, world, almanac) 0 across 321 renders. `selene` not run
(the Roblox std download fails here). **Nothing was played in Studio.**

### Calls made where the request left room

- **Scaling guards**: the shorter-edge rule alone squeezed the 900-wide layout on 4:3 windows
  (overlaps at 960x720 and 800x600), so the scale is also capped at width / 900, and on windows under
  ~900 px wide low enough that Cash clears the top-left chat footprint (230 px or 30%). Phones and
  normal desktops are unaffected.
- **Touch cap per device**, not per last input: a touch laptop would otherwise rescale the whole HUD
  between 1.0x and 1.25x on every switch.
- **Weather row is always a chip** (navy in the hub, event color from T-5:00): a plain text row can't
  keep the 8 px drawn spacing.
- **WATER label on two lines** ("WATER" / "· 2x 30s"): one line doesn't fit the 132 px button.
- **Mid-right SHOP/WATER sit under the column's tallest state**, not its current one, so they never
  move when Instant Weather or the bundle appears or goes. That pushed the hub SHOP from 88 to 80 tall
  to clear the jump button on an 800x360 phone; it is still the biggest button.
- **Glyph shadows** are a CanvasGroup faded as one layer (no seams). If CanvasGroups look soft or cost
  too much on low-end phones, set `Config/Hud.glyph.shadowTransparency = 0` (solid shadow) first.
- **Tray: wrap instead of widen.** A wider tray (440, then ~500 for Gem names) would push WATER/SHOP
  mid-right on 1280x720 and still clip Gem/Pumpkin pairs, so owned names wrap at their spaces and the
  next tile's "AT THE EGG SHOP" is two lines under its name; tiles grew 104 -> 116 tall (tray 158,
  Next Up 12 px higher) instead. The tray stays 424 wide.
- **Next Up slides left** (only when the mid-right buttons reach over its row) rather than moving
  the buttons back up into the right column's space.
- **Preview font**: Inter was narrower than Montserrat Black and hid squeezed text; the estimate and
  every text check now run against Montserrat. Counting outlines in every overlap check exposed
  1-3 px touches in the Almanac (picked tab / grid / pager, the big diamond's tip) and the Pumpkin
  card ("ENDS IN" ribbon under the % button); fixed by spacing, not by loosening the checks.

## Needs a Studio look

Nothing on the Roblox side runs headlessly; the preview approximates GothamBlack with Inter, CanvasGroup
fades, 3D viewports and gradient text.

1. **Icon legibility**: the eight glyphs at 1.0x on a real phone and at 1.25x on a monitor; the glyph
   shadow's CanvasGroup fade (not rendered by the preview) and its resolution on a low-end device.
2. **Soil tile on a phone**: the "+" and the price legible from the default camera; the tile reads the
   right way up from the gate side (`WorldUI.soil.rotation = 180`); the pulse during the tutorial's
   plant step, static after.
3. **Almanac track at 399** (and 5 / 24 / 26): marker and label legibility, real GothamBlack label
   widths (collapse to icons), phone tap targets at 667x375, the tooltip and how it dismisses.
4. **Scaling** at a real 1080p / 1440p monitor, a 1663x726 window, a 4:3 window and a phone; the touch
   cap on a touch laptop (one scale, no rescaling when switching input).
5. **WATER**: the two-line label at 1.0x on a phone, the drain ring, the dimmed state, the first-use
   toast on a live server; the "2x" chip on each growing egg's timer is not clipped.
6. **Egg timer height**: if the bar sits lower than ~4.2 studs over the patch, the BillboardGui's
   `SizeOffset` direction is the other way: negate `SlotTimer.SIZE_OFFSET`.
7. **Egg tray**: Roblox's TextScaled wraps "STARTER GEM" / "🎃 PUMPKIN" onto two lines at 14 px
   (rather than shrinking) in the 34 px name box; the "\n" in "AT THE" / "EGG SHOP"; scrolling with
   3+ eggs; the next tile opening the shop.
8. **Mid-right SHOP/WATER** on a phone with Instant Weather + the bundle showing (the first session),
   clear of the jump button; Next Up's Lab line (9.2 px on the smallest phone) legible.
9. **Gate sign** income line on both lines of the board (see open decisions).

Still open from earlier sessions (unchanged): the M5 list (Discord relay go-live, MemoryStore claim
across servers, global schedule on two servers, announcements, Instant Weather, Rebirth Now and the
Altar sign, the Pumpkin Egg end to end), the reconciliation list (VIP chat tag, purchase sparkle from
a second client, both boards with 3 players, group offer + PromptJoinAsync, Altar pad, pins, offline
Auto-Harvest on a real rejoin) and the Egg Shop/economy list (drag feel, wheel direction, edge-hover
auto-scroll, Gem eggs end to end, real first-rebirth time, mid-session Lab unlock). Details in the
previous handoff: `git show 53b4844:docs/HANDOFF.md`.

## Open decisions

- **Gate sign wraps**: "$0/min · plant eggs to earn" breaks onto two lines on its 300x60 board ("earn"
  alone on the second line, ~20 canvas px). Shorter text ("$0/min · plant to earn") or a wider board?
- **Almanac tier tabs** squeeze their text in the real font: "Starter 0/67" and "Swamp 0/67" draw
  smaller than "Lab 0/67", and "Cosmic 26/66" wraps (7 tabs share 728 px). Shorter labels (the
  count only on the picked tab?) or two rows of tabs? Not part of this pass.
- **Almanac track** draws only the last passed milestone (gold, checked), not every earlier one; the
  segment starts there. Draw all passed markers in gold on the left?
- **Cash and Gems** are 8 px apart frame to frame, so only ~1 px shows between Cash's shadow and the
  Gems outline. The tiles and column now use the as-drawn rule; extend it to the top row?
- **Top-left chat**: the chat is configured bottom-left; the preview still keeps the HUD out of
  Roblox's default top-left chat as a hedge (and the scale bound above follows it). Drop the hedge
  once Studio shows the chat never opens top-left.
- From before (unchanged): paying Rebirth 4 on day 2 vs the day-1 target; Skip Timer pricing (a
  soft-launch flag); pen income small by design; `#100+` outside the top 100; daily streak and
  Starter Bundle vs DESIGN.md; all pass/product ids, `Game.groupId` and `Game.gameLink` still unset.

## Next tasks, in order

1. **Publish the M5 build now** (the Pumpkin window runs until Nov 5 23:59 EST) after a Studio pass of
   the Pumpkin Egg (previous handoff, item 7) and the HUD list above; fix what the phone shows.
2. **Relay go-live**: `tools/relay/README.md` steps 1-4, then the relay and MemoryStore checks.
3. **Studio pass** on the rest of the lists above.
4. **Creator Hub setup**: passes, Gem packs, Starter Bundle, the group; fill the ids
   (`Config/Passes.lua`, `Config/Products.lua`, `Config/Game.lua` groupId) and the real `gameLink`.
5. **Decide the open UI questions** above (gate sign text, passed Almanac markers, Cash/Gems gap).
6. **Next limited egg** (Winter): one `Config/LimitedEggs.lua` entry + 10 species in
   `tools/gen-mutants.luau` `LIMITED` (re-run it); a new egg look needs a pattern in
   `MutantModel.buildEgg`, new hub props a `decor` builder in `World.lua`.
7. **M5 remaining**: VIP egg, first-session phone check, icon/thumbnail A/B; daily streak and Starter
   Bundle vs DESIGN.md (decide, then align).

Keep the rules in CLAUDE.md: server-authoritative intents, numbers only in Config, pink only for
spending, HUD below the GuiService inset, previews and checker at 0 issues.
