# Handoff — 2026-10-28 (Reconciliation)

Read `CLAUDE.md` first (rules, conventions, balance tables, commands) and `docs/DESIGN.md` (intent).
This file is what a fresh session needs on top of them: what changed in the last session, what has
never run in Studio, what is still undecided, and what to do next, in order.

Repo: https://github.com/BattleFrogsOfficial/mutant-farm (branch `main`). The place
file is built with `rojo build default.project.json -o MutantFarm.rbxl`. Tools: `bash tools/install-tools.sh`.

## What was done this session: Reconciliation with docs/DESIGN.md

Five commits (`f5293c7`, `fa87372`, `18b88c6`, `cb21d53`, and this docs commit), each with check,
tests, stylua and both previews green.

1. **Pen income** (`Config/Game.lua`, `Valuation.penIncome`, `DataService.penIncome`,
   `IncomeService`): 0.0005/min online, 0.0001/min offline of base value (tier x rarity only) x
   the rebirth multiplier (not VIP or group). A plain mutant pays back its sell value in 33.3 h
   (tested). The 8 h offline cap came in with the old 2%/min rate (commit `10c7af6`; the doc's
   original rule had none), so it's removed. Payouts carry fractions between minutes.
2. **Rebirth sells the bag** (`RebirthService`, `EconomyService.sellItem`): every mutant outside
   the pen is sold at full value through `addCash` (logged, counted in `totalCashEarned`), then Cash
   resets to `startingCash`, so the sale's Cash goes with it, as the doc says ("sold
   automatically first, then Cash ... reset"). Tested: 3 bagged mutants -> earned += their value.
3. **Offline Auto-Harvest** (`shared/AutoHarvest.lua`, `GrowthService.catchUp`): at join, every
   grow cycle while away is replayed in time order: harvest to the bag, replant the same egg
   (from the bag of eggs, else bought with Cash; Gem eggs never auto-bought), until the bag is full
   or Cash runs out. Mutation rolls on those cycles obey the 2 h cap. Online Auto-Harvest buys eggs
   the same way now (doc: "replants the same egg, paying from Cash"). Welcome back shows
   "auto-hatched". Tested: 3 h of Swamp eggs fills the bag and spends Cash; nothing grown entirely
   after the cap mutates.
4. **VIP** (`ChatController`, `MonetizationService`, `DailyService`, `DailyPanel`): gold `[VIP]`
   chat prefix via `TextChatService.OnIncomingMessage` from a `VIP` player attribute; 50 Gems per
   UTC day from a VIP strip in the Daily panel (`ClaimVipGems`, red dot on the Daily icon). Tested
   (claim once per day). VIP egg stays M5.
5. **Weather** (`Config/Weather.lua`, `shared/WeatherRules.lua`, `WeatherService`): 120 s events,
   a roll at the start and every 30 s (4 rolls): 25 / 30 / 10% per tick; weights 50/50/20 (Glitch
   Storm 1 in 6). HUD countdown chip in every zone from 5 min before (`Hud.weatherText`). Tested:
   100 Acid Rain events through the real service mutate 60-75% of fully grown-through eggs.
6. **Leaderboards** (`LeaderboardService`, `shared/Leaderboards.lua`, `LeaderboardController`,
   `World.leaderboards`): Top Pens (pen value at x1) and Top Rebirths, OrderedDataStores
   `TopPens_v1` / `TopRebirths_v1`, top 100 each, saved + re-read every 120 s (and saved on leave),
   sent to clients; drawn as scrolling SurfaceGuis in PlayerGui adorned to two boards at the north
   edge of the plaza, with your own row pinned at the bottom. The old `CashEarned_v1` board is gone.
7. **Pins** (`shared/Pen.lua`, `Pin` intent, `SellPanel`, `HatchScreen`): pinned mutants always
   stand in the pen (cap 8), Sell All skips them, rebirth keeps them; 📌 toggle on each Sell panel
   row and "PIN TO PEN" on the hatch reveal. Tested.
8. **Purchase effects** (`MonetizationService.purchaseFx`, `PlotController`, `ChatController`):
   every Robux purchase sends `PurchaseFx` to the whole server: a gold/pink sparkle burst over the
   buyer's plot; VIP and the Starter Bundle also post a system chat line. Tested (server side).
9. **Group reward** (`GroupRewardService`, `GroupOfferPanel`): IsInGroup on join; offered once
   after the first sale (Join opens `GroupService:PromptJoinAsync`, then `ClaimGroupReward`); a
   non-member's sales re-check with `GetGroupsAsync` (at most every 30 s). Tested: joining
   mid-session pays +10% on the next sell; offer shown once.
10. **Rebirth Altar** (`World.rebirthAltar`, `ZoneController.altarSign`, `PlotController` pads):
    violet step-on pad on the plaza's south edge (opposite the boards, across the fountain) with
    small Neon stones and one weak light; the sign shows "REBIRTH N · $cost" / "unlocks <tier>"
    (or "Cash xN") and a Cash/cost bar. World checker 0 issues; rendered legible at 667x375.
11. **Unlinked ids**: Studio prints one warning listing every pass and product with id 0. Tested.
12. **Simulator** (`tools/sim.luau`): models the pen, the new income rates, Auto-Harvest from
    Cash and the rebirth sale. 60 runs, 1.5 active h/day:

    | Bot | Rebirth 1 | Free R4 / R10 | Paying R4 / R10 |
    |---|---|---|---|
    | Sells everything (default) | 25 sim-min | day 3 / not in 30 days | day 2 / day 16 |
    | Keeps its 8 best (`--pen keep`) | 917 sim-min | day 6 / not in 30 days | day 5 / day 18 |

    The default bot is unchanged from before: it sells everything, so it never has a pen to earn
    from, and its bag is already empty when it rebirths. Rebirth 1 is inside 25-30, so no retune.
    Keeping the 8 best early mutants withholds the big early hits that fund the first rebirth.
13. **Tooling**: `tools/server-harness.luau` runs the real server services under Lune (fake
    players, clock, ProfileStore, OrderedDataStores, Marketplace/Group services); `tests/server.spec`
    and `tests/weather.spec` use it through `t.server()`. `install-tools.sh` now builds stylua with
    `--features luau` (without it stylua can't parse a single file).

Verified at the end: `lune run tools/check` (102 files), `lune run tools/test` (83 pass), world
checker 0 issues (2011 parts), UI preview 0 HUD issues (24 combinations) and 0 shop issues (30
scenes), stylua clean. `selene` was not run (the Roblox std download fails here).

## Untested in Studio

Nothing on the Roblox side runs headlessly. New this session:

1. **VIP chat tag** shows gold `[VIP]` before the name (TextChatService must be the chat version;
   `OnIncomingMessage` is the only callback set). System chat lines appear in RBXGeneral.
2. **Purchase sparkle** is visible from another client in a 2-player test (Studio test purchases;
   set a pass id first, e.g. VIP).
3. **Both boards populate** in a test server with 3 players (DataStores need API access in
   Studio, or a published place); scrolling works and your own row shows `#N` / `#100+`.
4. **Group offer**: `GroupService:PromptJoinAsync` opens Roblox's prompt; on Joined the bonus and
   eggs apply; set `Game.groupId` first. Daily panel strips (group, VIP) fit with both visible.
5. **Rebirth Altar**: stepping on it opens the Rebirth panel; the sign text and bar update; the
   glow is soft (no glare).
6. **Pins**: 📌 on Sell rows and PIN TO PEN on the reveal; the pen on the plot shows pinned ones.
7. **Weather chip** appears 5 min before an event in both zones on a phone.
8. **Offline Auto-Harvest** on a real rejoin (Welcome back shows "auto-hatched"; no toast flood).

Still open from the previous session (unchanged):

9. **Shop no longer closes on clicks.** The `Blocker` fix follows a diagnosis that couldn't be
   reproduced headlessly. Click every part of the open shop (card faces, side cards, title row,
   empty panel space, dots) and confirm only the X and the backdrop close it. Also check other
   panels still work with the Blocker.
10. **Drag feel:** 1:1 follow, flick distance (`EggShopUI.flickSeconds` 0.12), tap slop (8 px),
   overshoot at the ends (0.35 cards). Does `InputBegan` on the Strip fire when the press starts on
   a card or a buy button? (Tap-to-focus and drag rely on it.)
11. **Wheel direction:** `Carousel.wheel` treats `Position.Z > 0` (wheel up) as left. Confirm it feels
   right, and that the wheel no longer zooms the camera while the shop is open.
12. **Left/Right camera sink:** with the shop open, Left/Right must step the carousel and must not
   turn the camera; Enter buys x1. After closing, arrow keys and the wheel behave normally again
   (unbind).
13. Edge-hover auto-scroll: only on mouse devices, only on the strip's outer edges, pauses after a
   click until the mouse leaves the zone.
14. Dim backdrop covers every edge including under the top bar; tapping it closes the panel; it
   hides during the hatch cutscene.
15. Gem eggs end to end (buy, plant, hatch with the crystal egg, rebirth keeps them), the potion
   from the shop title row, and a PolicyService-restricted account (no switch, no potion).
16. Real first-rebirth time with Lab at 5K and Rebirth 1 at 700K (target 35-45 real minutes).
17. Mid-session unlock: earn past $25K with the shop open -> Lab flashes, jingle once, NEW ribbon.

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
- All pass/product ids and `Game.groupId` are 0 until created in Creator Hub (Studio now warns).
- **Pen income is small by design** (33 h payback): a pen of Starter/Swamp Commons earns a few
  dollars a minute at most (the HUD reads "+$0 / MIN" and the gate sign stays blank below $1); the Daily "minutes of Cash" rewards
  lean on their `min` floors now. The design says "the pen never short-circuits a rebirth
  threshold", and the sim agrees; check that it still feels worth pinning.
- **Own rank outside the top 100** shows `#100+`: OrderedDataStore has no rank lookup, and
  paging to find it would blow the GetSortedAsync budget.
- **Top Pens** values pens at x1 (no Cash multiplier), so it compares mutants, not rebirths.
- **Not in this reconciliation, still different from DESIGN.md:** the daily streak pays eggs and
  Cash (doc: Gems on days 1-6, Toxic egg day 7); the Starter Bundle grants 550 Gems (doc: 500
  Gems + 2 Luck Potions).


## Next tasks, in order

1. **Studio pass on the reconciliation** (items 1-8 above): 2-3 player test server, test
   purchases with a pass id set, the group with `Game.groupId` set. Fix anything found.
2. **Studio pass on the Egg Shop and economy** (items 9-17): time a real first rebirth; record it
   in CLAUDE.md next to the sim number.
3. **Decide the rebirth tail** (x5 vs ~x4.45); if it changes, re-run
   `lune run tools/sim -- --runs 60` and update the table in CLAUDE.md.
4. **Creator Hub setup:** create the game passes, the Gem pack developer products, the Starter
   Bundle and the group; fill the ids in `Config/Passes.lua`, `Config/Products.lua` and
   `Config/Game.lua` (`groupId`); the Studio warning goes quiet when all are linked.
5. **Daily streak and Starter Bundle vs DESIGN.md** (see Open decisions): decide, then align.
6. **M2 remaining:** final sounds in `Config/Assets.lua`.
7. **M5 / week-6 list:** limited egg, VIP egg, Instant Weather + Rebirth Now, weather announce +
   Discord relay (Cloudflare Worker), first-session phone check. Egg skins stay v1.5.

Keep the rules in CLAUDE.md: server-authoritative intents, numbers only in Config, pink only for
spending, HUD below the GuiService inset, previews and checker at 0 issues.
