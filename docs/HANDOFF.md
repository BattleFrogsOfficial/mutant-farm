# Handoff — 2026-10-28

Read `CLAUDE.md` first (rules, conventions, balance tables, commands). This file is what a fresh
session needs on top of it: what changed in the last session, what has never run in Studio, what is
still undecided, and what to do next, in order.

Repo: https://github.com/BattleFrogsOfficial/mutant-farm (branch `main`). The place
file is built with `rojo build default.project.json -o MutantFarm.rbxl`.

## What was done this session

### `2a5262d` Balance revision and Egg Shop carousel

- **Tier unlocks:** Lab moved to Rebirth 0, gated on $25,000 lifetime Cash earned
  (`stats.totalCashEarned`, incremented in `EconomyService.addCash`; migrated from the old
  `stats.cashEarned` after Reconcile). Toxic Rebirth 1, Void 3, Cosmic 6. All unlock checks go
  through `src/shared/ShopRules.lua` (`isUnlocked`, `nextLocked`, `newlyUnlocked`, `price`,
  `canBuy`, `canBuyPotion`).
- **Rebirth cost formula:** `Rebirths.firstCost x costGrowth ^ rebirths` replaced the hand-tuned
  table (first set to 250K x5; changed again in `6a84e70`).
- **Gem egg variants** `<Tier>Gem` generated in `Config/Eggs.lua`: prices 15 / 40 / 120 / 300 /
  800 / 2,000 Gems, Uncommon+ odds x2 renormalized, same unlock gates, crystal overlay on the egg
  model, policy-gated (server refuses when restricted or unknown), Gems sink `GemEgg_<Tier>`,
  funnel step `FirstGemEgg` (its own single-step funnel `GemEggs`). Harvested items keep
  `item.tier` = base tier and `item.egg` = the egg id. Gem eggs survive rebirth.
- **Taglines** for every tier in `Eggs.lua` (shown on further-locked shop cards).
- **Egg Shop carousel** replaced the grid (`src/client/UI/EggShop.lua`, math in
  `src/shared/Carousel.lua`, layout numbers in `src/shared/Config/EggShopUI.lua`): focused center
  card, drag/arrows/wheel/keys, desktop edge-hover auto-scroll, Cash | Gems switch that morphs cards
  in place, buyable / next-locked (progress card) / further-locked states, NEW ribbon + flash +
  Rare jingle on mid-session unlocks, policy-restricted players see no switch and no potion.
- Review fixes folded in: the progress bar fills only when the tier is one rebirth away (else
  "N rebirths to go"); NEW ribbons count a visit when the panel goes to "none" (hopping to the Gem
  shop doesn't count; an unlock during a visit doesn't count that visit); StateController never
  auto-selects a Gem egg; `FirstGemEgg` logged with `LogFunnelStepEvent`.
- Tools: `tests/shop.spec.luau`, `tests/carousel.spec.luau`; sim tracks earnings and uses
  `ShopRules`; UI preview got carousel scenes and checks; the preview renderer now applies UIScale
  about the AnchorPoint like Roblox; `ONLY=<prefix>` limits screenshots.

### `6a84e70` Rebirth 1 at 700K with Lab back at 5K; smoother, bigger carousel

- **Balance decision (from the designer):** don't tune pacing with the Lab price. Lab back to
  **5K** (keeps the 50 -> 500 -> 5,000 ladder; at 45K the sim's player barely bought it). Rebirth 1
  = **700K**, then **x5** (3.5M, 17.5M, 87.5M, ...).
- **Sim results** (60 runs, 1.5 active h/day): first rebirth **25 sim-min** (~33-40 real minutes:
  the sim plays perfectly). Free: Rebirth 1 day 1 (0.4 h), Rebirth 4 **day 3**, Rebirth 9 day 17,
  Rebirth 10 **not within 30 days**. Paying (2x Luck + Auto-Harvest): Rebirth 4 day 2, Rebirth 10
  **day 16**. Before (250K x5): free Rebirth 10 day 22, paying day 11. New `--growth X` sim option:
  x4.3 -> free R10 day 18 / paying day 10; x4.6 -> day 26 / day 12 (30 runs each).
- **Egg Shop fixes after the first Studio play:**
  - Clicks on the shop closed it. Diagnosis (not reproduced headlessly): clicks on non-button
    parts of a panel fell through to the full-screen dim button, which closes panels. Fix: every
    `C.panel` (`UI/Components.lua`) has a transparent full-size `Blocker` TextButton behind its
    content.
  - One arrow click ran to the far end: the edge-hover auto-scroll zone covered the arrow buttons.
    The zone is now the strip's own outer 15%, and auto-scroll pauses after any click/key/wheel
    until the mouse leaves the zone.
  - Bigger: panel 860x470 (was 780x404), center card 240x320, side cards 0.6x.
  - Smoother: the strip glides toward a target (`Carousel.approach`, ~0.2 s, retargets
    mid-glide), cards scale (`Carousel.scaleAt`) and fade (`Carousel.veilAt`) continuously with
    distance, drag flicks (0.12 s velocity projection), tap a side card to center it.
  - Gem mode shows the tier name ("Swamp Egg"); the gem is on the egg art and the
    "💎 2x RARITY ODDS" badge ("Swamp Gem Egg" fell to 12.5 px on phones; now 16.8 px).
  - Left/Right/Enter and the mouse wheel are bound with
    `ContextActionService:BindActionAtPriority` (High) while the shop is open and return `Sink`;
    unbound on close.
  - The dim backdrop moved to `UI/Backdrop.lua` in its own ScreenGui (`IgnoreGuiInset = true`,
    DisplayOrder 0 under the main GUI's 1) so it covers the whole screen including the top-bar
    strip.

### Docs commit (this handoff)

`CLAUDE.md` restructured under 200 lines (conventions, status by milestone, live balance, one
Commands section); the dated change notes moved here.

Verified at the end of the session: `lune run tools/check` (91 files), `lune run tools/test`
(64 pass), world checker 0 issues (1989 parts), UI preview 0 HUD overlaps (24 combinations) and
0 shop issues (30 scenes). `selene` was not run (needs internet for the Roblox std).

## Untested in Studio

None of this has been exercised in a real Roblox client; the headless preview only checks layout.

1. **Shop no longer closes on clicks.** The `Blocker` fix follows a diagnosis that couldn't be
   reproduced headlessly. Click every part of the open shop (card faces, side cards, title row,
   empty panel space, dots) and confirm only the X and the backdrop close it. Also check other
   panels still work with the Blocker.
1. **Drag feel:** 1:1 follow, flick distance (`EggShopUI.flickSeconds` 0.12), tap slop (8 px),
   overshoot at the ends (0.35 cards). Does `InputBegan` on the Strip fire when the press starts on
   a card or a buy button? (Tap-to-focus and drag rely on it.)
2. **Wheel direction:** `Carousel.wheel` treats `Position.Z > 0` (wheel up) as left. Confirm it feels
   right, and that the wheel no longer zooms the camera while the shop is open.
3. **Left/Right camera sink:** with the shop open, Left/Right must step the carousel and must not
   turn the camera; Enter buys x1. After closing, arrow keys and the wheel behave normally again
   (unbind).
5. Edge-hover auto-scroll: only on mouse devices, only on the strip's outer edges, pauses after a
   click until the mouse leaves the zone.
6. Dim backdrop covers every edge including under the top bar; tapping it closes the panel; it
   hides during the hatch cutscene.
7. Gem eggs end to end (buy, plant, hatch with the crystal egg, rebirth keeps them), the potion
   from the shop title row, and a PolicyService-restricted account (no switch, no potion).
8. Real first-rebirth time with Lab at 5K and Rebirth 1 at 700K (target 35-45 real minutes).
9. Mid-session unlock: earn past $25K with the shop open -> Lab flashes, jingle once, NEW ribbon.

## Open decisions

- **Rebirth tail multiplier.** x5 after 700K pushes free Rebirth 10 past day 30 (was day 22) and
  paying to day 16 (was 11). ~x4.4-4.5 restores the old tail while keeping 700K and day-3 Rebirth 4.
  Kept at x5 (the agreed chain) pending a decision. Change only `Config/Rebirths.lua` `costGrowth`
  and the tests in `tests/economy.spec.luau`.
- **Paying player Rebirth 4** lands day 2; the stated target was day 1.
- **Skip Timer pricing** is a soft-launch tuning flag (`Config/Products.lua` comment): if Skip
  revenue is high while day-3 return is low, price on total remaining minutes instead.
- **Gem badge on side cards:** the "2x RARITY ODDS" badge also shows (tiny) on unlocked side cards,
  per the spec ("on unlocked cards"); the spec also says side cards show only egg and name. Pick one.
- All pass/product ids and `Game.groupId` are 0 until created in Creator Hub.

## Next tasks, in order

2. **Studio pass on the Egg Shop** (items 1-6 above). Fix anything found; tune feel only through
   `Config/EggShopUI.lua`.
3. **Studio pass on the economy** (items 7-9): time a real first rebirth; record it in CLAUDE.md
   next to the sim number.
4. **Decide the rebirth tail** (x5 vs ~x4.45); if it changes, re-run
   `lune run tools/sim -- --runs 60` and update the table in CLAUDE.md.
4. **Creator Hub setup:** create the game passes, the Gem pack developer products, the Starter
   Bundle and the group; fill the ids in `Config/Passes.lua`, `Config/Products.lua` and
   `Config/Game.lua` (`groupId`); test purchases in Studio. (Luck Potion and Skip Timer are paid in
   Gems, so they need no ids.)
5. **M2 remaining:** player-chosen "Keep in pen"; final sounds in `Config/Assets.lua`.
6. **M5 / week-6 list:** limited egg, Instant Weather + Rebirth Now, weather announce + Discord
   relay (Cloudflare Worker), first-session phone check. Egg skins stay v1.5.

Keep the rules in CLAUDE.md: server-authoritative intents, numbers only in Config, pink only for
spending, HUD below the GuiService inset, previews and checker at 0 issues.
