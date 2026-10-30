# Handoff — 2026-10-30 (HUD style unification and panel overhaul)

Read `CLAUDE.md` first (rules, conventions, live numbers, commands) and `docs/DESIGN.md` (intent; dated
rule changes at the top). This file is what a fresh session needs on top of them: what changed in the
last session, what has never run in Studio, what is still undecided, and what to do next, in order.

Repo: https://github.com/BattleFrogsOfficial/mutant-farm (branch `main`). Tools: `bash tools/install-tools.sh`.
Place file: `rojo build default.project.json -o MutantFarm.rbxl`.

**The Pumpkin Egg window is open now** (2026-10-29 00:00 EDT to 11-05 23:59 EST). The M5 build and
everything below have still not been published or played in Studio; see "Next tasks".

## What was done this session

The nine-item HUD unification. No balance change except the new Gem upgrades (item 4).

| Commit | Item |
|---|---|
| `9e80c9d` | 1 Icon system: `UI/Icons.lua` (renamed from Glyphs) with 19 asked glyphs + 9 more; `C.icon` / `C.iconText` / button `Icon`/`IconAfter`; every emoji in the HUD and panels replaced; `tests/icons.spec.luau`; Almanac stacked labels (see 6) |
| `50f95e8` | 7 $/min: income = expected Cash/min of the eggs growing now (`Expected.growingPerMinute`) + pen; harness test |
| `de0ce32` | 3 Starter Bundle ribbon: gold, ink text, gift glyph, countdown below, 2 s pulse |
| `d45d712` | 4 WATER label, Upgrades panel rebuilt (shop chrome, Cash + Gem sections), Gem upgrades (`BuyGemUpgrade`) |
| `7b8d516` | 8 Weather line centered under Cash / Gems in every zone; toast lane under it |
| `182fb40` | 5 Daily panel: shop-style day cards |
| `5d65ba8` | 2 Text sizes: the preview's Text check (14 px, 16 for numbers) and every fix it needed |
| (this one) | 9 Docs: CLAUDE.md UI section, DESIGN.md note, this handoff |

1. **Icons**: coin gem gift book arrowUp bag egg drop cart lock sun radiation bolt sparkle pumpkin
   check clover star flame, plus group pin paw rebirth sprout robot crown moon skip. Small glyphs
   (< 24) shrink their outline and shadow. Weather events and limited eggs carry a `glyph` in config
   (`icon` emoji stays for chat lines and world signs). Toasts strip emoji from server text.
2. **Text sizes**: see "Calls made" for how the rule is measured.
3. **Bundle ribbon**: the only gold button; Sell / Welcome / Daily claim / Rebirth confirm went navy.
4. **WATER** "2x GROWTH" / "FOR 30s", no ring, "2x ACTIVE" + seconds dimmed. **Upgrades panel**
   640x440: CASH UPGRADES (Growth Speed, Mutation Odds) and GEM UPGRADES (Pen Slots 150 once per
   rebirth level, Permanent Luck 200/400/800, Offline Mutations 100/200/400, MAX with the pass). Gem
   upgrades live in `Config/Upgrades.gem` and `shared/GemUpgrades.lua`, `profile.gemUpgrades`, kept
   through rebirth; `DataService.penCapacity` / `luck` / `oddsBonus`; sink `GemUpgrade_<kind>`.
5. **Daily**: 7 cards (88 wide, Day 7 128) with the real egg model, a coin stack + "$ x10" /
   "MINUTES" for Cash, gem glyph for Gems (none in the config yet); claimed green + check, today
   pulsing gold + CLAIM, later dimmed + lock; streak line with flame; bottom button claims or counts
   down. Group and VIP strips unchanged.
6. **Almanac track**: the owner's mid-task change replaced the requested glyph labels: each label
   is two stacked lines, words only ("100" over "Toxic Egg", "400" over "+10% luck"), no round
   glyphs. Markers keep their reward tier's color; all passed milestones gold with a check. Shipped
   inside `9e80c9d`, so there is no separate item-6 commit.
7. **$/min**: it stayed $0 because `incomePerMinute` was only the pen. Now pushed in the snapshot
   on every plant, harvest, sell, water, pass change and rebirth (they all already send a snapshot).
   Test: 2 Starters planted, 60 s later income > 0, about 2x while watered.
8. **Weather line**: plain glyph + text ("SOLAR FLARE IN 9:24"), a chip in the event's color from
   T-5:00 ("... IN 4:12", then "SOLAR FLARE · 1:42 LEFT"); `Config/Hud.weather` y 78, toasts y 118.

**Verified at the end:** `lune run tools/check` 129 files, 0 failed · `lune run tools/test` 133
passed · `stylua --check` clean · `node tools/relay/test.mjs` passed · world checker 0 issues (2027
parts, with and without `LIMITED_AT`) · full UI preview (Montserrat, 10 sizes, 450 scenes): Text 0
across 450 scenes, Shop 0 across 80, Panel 0 across 30, extra checks 0 across 351 renders. The full
run found one HUD issue (the larger group badge touching the Rebirth strip and the weather line);
after the fix `ONLY=hud` re-ran HUD overlap 0 across 280 state x size combinations and extras 0
across 300. `selene` not run. **Nothing was played in Studio.** No review pass was run (the owner's
rule: reviews are for the launch build).

### Calls made where the request left room

- **Text sizes are design px**: 14 / 16 px on the 900x540 canvas, measured as on-screen px divided
  by the HUD scale. At 800x360 the scale is 0.56, so 14 *screen* px would need 25 design px
  everywhere and the HUD would no longer fit a phone. "Number" = any text with "$", or only digits,
  signs and units ("x3", "26/66", "400"); text like "25 Gems" counts as words (14).
- **Egg Shop side cards** are drawn at 0.6x by design, so the locked cards' condition and tagline are
  24 design px (14 on screen at 0.6x, `EggShopUI.furtherText`).
- **Daily Cash rewards still pay `penIncome`**, not the new income: the new $/min includes growing
  eggs, which would have raised the Day 3 / Day 6 rewards (a balance change).
- **Shorter texts** to fit at full size: tray hint "TAP SOIL TO PLANT" (was "PICK AN EGG · TAP
  SOIL"); shop grow line "Grows 5m · sells $900+"; Almanac limited species show the pumpkin glyph
  instead of "LIMITED · Halloween 2026" (the tab already says it).
- **Store pass cards** are two per row (284x118) so their descriptions fit at 14 px; the Store panel
  scrolls a little further.
- **The bundle countdown** in the Store banner is 16 px; the HUD ribbon's is 18 px on its own line.
- **Three-strike rule**: nothing hit it.

### Follow-up: Almanac labels centered on their diamonds

The 100 and 400 labels (and 200 / 300, less visibly) were slid sideways to fit: 400 by the track's
right end, 100 by the next milestone's label. Now every label is centered on its marker; the bar's
ends are inset for the first/last label; a big label that can't fit beside the next one shows its
number alone, then hides (tap the diamond for the tooltip). Trade-off: while the next milestone is
25-50 species before a big one (e.g. 26-74 found for 100), that big reward isn't spelled out under
its diamond. New preview check: each drawn label line within 1.5 px of its diamond's center (it
flags 106 offsets on the old layout, 0 now).

## Needs a Studio look

Nothing on the Roblox side runs headlessly; the preview approximates GothamBlack with Montserrat
Black, CanvasGroup fades, 3D viewports and gradient text.

1. **Glyphs** at 1.0x on a phone and 1.25x on a monitor: the 28 shapes, the small ones (14-20 px)
   with their thinner outline, the CanvasGroup shadow on a low-end device.
2. **Daily panel**: egg viewports on the cards (the preview draws grey blobs), the pulsing gold
   border, CLAIM on the card and the bottom button both claiming, the Day 7 spin.
3. **Upgrades panel**: buy each Gem upgrade, Pen Slots after a rebirth (one more level), the pen
   showing 12 mutants, Permanent Luck under the 6x cap, Offline Mutations MAX with the pass, the
   short-on-Gems jump to the Gem shop.
4. **$/min** on the Cash panel and the gate sign right after planting, while watered, after a sale
   and after a rebirth.
5. **Weather line** in the hub and at the plot: idle text, the T-5:00 chip, active, and toasts under
   it; the group badge and the Rebirth strip beside each other.
6. **Text** on the smallest phone (667x375): Almanac labels and tabs, the tray, Next Up, Store pass
   cards; real GothamBlack widths vs the Montserrat estimates.
7. **Starter Bundle ribbon**: gold, the 2 s beat, the countdown.

Still open from earlier handoffs: the HUD Studio list in `git show 12e50ad:docs/HANDOFF.md`, and the
M5 / reconciliation / Egg Shop lists in `git show 53b4844:docs/HANDOFF.md` (the Pumpkin Egg end to
end first).

## Open decisions

- Gem rewards in the Daily calendar: the card supports `kind = "gems"`, but the config has none and
  `DailyService` doesn't grant them yet (adding them is a balance change).
- From before (unchanged): paying Rebirth 4 on day 2 vs the day-1 target; Skip Timer pricing (a
  soft-launch flag); pen income small by design; `#100+` outside the top 100; daily streak and
  Starter Bundle vs DESIGN.md; all pass/product ids, `Game.groupId` and `Game.gameLink` still unset.

## Next tasks, in order

1. **Studio today, Pumpkin first** (until Nov 5 23:59 EST): the Pumpkin Egg end to end, then the list
   above on a phone; fix what it shows; publish.
2. **Relay go-live**: `tools/relay/README.md` steps 1-4, then the relay and MemoryStore checks.
3. **Studio pass** on the older lists.
4. **Creator Hub setup**: passes, Gem packs, Starter Bundle, the group; fill the ids
   (`Config/Passes.lua`, `Config/Products.lua`, `Config/Game.lua` groupId) and the real `gameLink`.
5. **Next limited egg** (Winter): one `Config/LimitedEggs.lua` entry (with a `glyph`; a new shape goes
   in `UI/Icons.lua`) + 10 species in `tools/gen-mutants.luau` `LIMITED`.
6. **M5 remaining**: VIP egg, first-session phone check, icon/thumbnail A/B.

Keep the rules in CLAUDE.md: server-authoritative intents, numbers only in Config, pink only for
spending, glyphs not emoji, text at least 14 / 16 px, previews and checker at 0 issues, and the
owner's working rules (one single-reviewer pass for the launch build only, `ONLY=` in fix loops,
three strikes then commit and report, a commit per numbered item).
