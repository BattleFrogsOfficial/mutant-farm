# Handoff — 2026-10-28 (M5 build)

Read `CLAUDE.md` first (rules, conventions, live numbers, commands) and `docs/DESIGN.md` (intent; dated
rule changes at the top). This file is what a fresh session needs on top of them: what changed in the
last session, what has never run in Studio, what is still undecided, and what to do next, in order.

Repo: https://github.com/BattleFrogsOfficial/mutant-farm (branch `main`). Tools: `bash tools/install-tools.sh`.
Place file: `rojo build default.project.json -o MutantFarm.rbxl`.

## What was done this session

| Commit | Item |
|---|---|
| `7d60427` | A: rebirth tail x4.5, Gem badge on the focused card only, DESIGN.md as the intent doc |
| `137ce71` | B: limited eggs (generic) + the Pumpkin Egg |
| `394817d` | E: global weather schedule, announcements, Discord relay (+ Instant Weather server) |
| `80e5f2f` | C + D: Instant Weather and Rebirth Now (client), Rebirth Now server |
| (this one) | Docs: CLAUDE.md, DESIGN.md dated notes, this handoff |

- **A1 Rebirth tail** `Config/Rebirths.lua` costGrowth 4.5 (700K, 3.15M, 14.2M, 63.8M, ...). Sim, 60
  runs, 1.5 active h/day: Rebirth 1 at **25 sim-min** (unchanged); free Rebirth 4 **day 3**, Rebirth 10
  **day 23**; paying Rebirth 4 day 2, Rebirth 10 **day 11**. The open decision is closed.
- **A2** the "2x RARITY ODDS" badge only on the focused card in Gem mode (side cards: egg and name).
  The UI preview checks it.
- **A3** CLAUDE.md's header points at DESIGN.md; every rule change goes into both, dated in DESIGN.md.
- **B Limited eggs** `Config/LimitedEggs.lua` → tiers generated in `Eggs.lua` (outside `Eggs.order`),
  `ShopRules.activeLimited/isLimitedActive/shownLimited`, BuyEgg refuses outside the window ("ended") or
  when restricted, sink `LimitedEgg_<id>`, funnel `FirstLimitedEgg`. **Pumpkin Egg**: 600 Gems (x5
  3,000), 30 min, Lab values and size, Lab's Uncommon+ x2 renormalized, design `jack` (ridges, carved
  face, stem; no Neon), 10 Halloween species (bucket `Pumpkin`, 2 per rarity; new accessories
  `witchHat`, `stem`; also in `tools/gen-mutants.luau`), window unix 1793246400..1793941140 (Oct 29
  00:00 EDT .. Nov 5 23:59 EST, across the Nov 1 DST change). Shop: left-most slots in both modes,
  Gem-priced, live "🎃 ENDS IN 3d 4h" ribbon, first open focuses it (`SeenLimited`,
  `profile.seenLimited`) with NEW + flash, gone on the next open after `endsAt`. Tray/bag icon,
  Almanac tab + "LIMITED · Halloween 2026". World (at server start, inside the window): banner on the
  Egg Shop roof sign, three carved pumpkins around the fountain (`World.build(now)`; `LIMITED_AT` in
  the preview tools forces it).
- **C Instant Weather** 400 Gems: `BuyInstantWeather(eventId)` → a 120 s event on the buyer's plot only
  (WeatherService, same rolls as global weather, independent of it, never two at once), policy-gated
  like the potion, sink `InstantWeather_<id>`, player attributes `PlotWeatherId/EndsAt`. Pink HUD
  button (no global event running or within 5 min, none of yours, not restricted) → picker panel; Shop
  Gems section card; rain (+ static for Glitch Storm) over that island under a small cloud others see,
  tint for the owner on their plot.
- **D Rebirth Now** 100 Gems: `RebirthNow` from 50% of the cost: the exact rebirth flow, then the Gems
  (checked first); sink `RebirthNow`; not policy-gated. Pink button beside the bar in the Rebirth panel
  (two taps; short on Gems → Gem shop) and on the Rebirth Altar sign (now drawn per player by
  `UI/AltarSign` in a PlayerGui SurfaceGui so it can be tapped; it opens the panel).
- **E Weather** `shared/Weather.lua` `scheduleAt(t)`: 1500 s buckets counted from the unix epoch, event
  at +300 s for 120 s, type = seeded hash of the bucket index, 45/40/15. Every server runs the same
  events at the same time; the "first event 6 min after start" rule is gone. Announcements to the
  server: toast at T-5:00 (+ chat system line), T-1:00 and the start. Discord (Glitch Storm, T-5:00):
  MemoryStore claim (`WeatherAnnounce`, key = startsAt, UpdateAsync, 3600 s) → POST to `Game.relayUrl`
  with `WEATHER_RELAY_KEY` in `X-Relay-Key`. `tools/relay/` has the Worker, its README (setup) and a
  node test.
- **Tooling**: the server harness fakes MemoryStore, HttpService (GetSecret, RequestAsync), Analytics
  events (`world.economy`, `world.funnels`) and per-player policy (`world.restricted`). The UI preview
  got shop-limited (Cash/Gems/restricted), hud-instant-weather (hub/plot/restricted), instantWeather,
  rebirth-now (panel + altar) and a panel overlap check; ui-render waits up to 5 min for the (now
  ~60 MB) scene file.

**Verified at the end:** `lune run tools/check` 107 files, 0 failed · `lune run tools/test` 106 passed,
0 failed · `stylua --check src tools tests` clean · `node tools/relay/test.mjs` passed · world checker
0 issues with the Halloween decor off (2011 parts) and on (2027 parts, `LIMITED_AT=1793500000`) · UI
preview: HUD 0 issues across 42 state x size combinations, shop 0 across 48 scenes, panels 0 across 18
· sim as above. `selene` not run (the Roblox std download fails in this environment).

### Calls made where the request left room

- **"1500 s buckets aligned to the hour"**: 3600 isn't a multiple of 1500, so buckets are counted from
  the unix epoch (itself on an hour): every bucket is exactly 25 min, the grid meets the hour every
  5 h, and every server agrees. Resetting at each hour would make a 10-min last bucket.
- **Relay key**: Roblox `Secret` values can only go into headers or the URL, so the game sends the key
  in `X-Relay-Key`; the Worker accepts the header or a JSON `key`.
- **Altar Rebirth Now button** opens the Rebirth panel (where both buttons confirm with a second tap)
  instead of rebirthing straight from the sign.
- **Instant Weather** that's running when its buyer leaves just ends (no refund); global events can't
  be bought off.

## Untested in Studio

Nothing on the Roblox side runs headlessly. New this session:

1. **Discord relay**: deploy the Worker (tools/relay/README.md), add the `WEATHER_RELAY_KEY` secret,
   turn on Allow HTTP Requests, set `relayUrl`/`gameLink`; one message per Glitch Storm with two or
   more live servers. Check the secret works in the header (`HttpService:GetSecret` → `RequestAsync`).
2. **MemoryStore claim** across real servers (only one posts); and that Studio without API access
   just logs "relay skipped" once.
3. **Global schedule** on two live servers: same event, same second (the HUD chip matches).
4. **Announcements**: the three toasts and the T-5:00 chat line (TextChatService).
5. **Instant Weather**: picker feel; rain/static only over that island; the cloud visible from another
   client; the owner's tint only on their plot; the button hiding near global events and while yours
   runs; restricted account: no button, no Shop card.
6. **Rebirth Now**: panel button (two taps), the Altar sign button is tappable (PlayerGui SurfaceGui)
   and its text/bar update; short on Gems opens the Gem shop.
7. **Pumpkin Egg**: the shop opens on it once; ribbon countdown; buy x1/x5; the `jack` egg and the 10
   species look right (witch hat, stem); hatching; the Almanac tab; rebirth keeps the eggs; after Nov 5
   23:59 EST the card is gone on the next open. World banner + pumpkins on a server started inside the
   window. Restricted account: no card.

Still open from the previous sessions (unchanged): the reconciliation list (VIP chat tag, purchase
sparkle seen from a second client, both boards with 3 players, group offer + PromptJoinAsync, Altar
pad, pins on Sell rows/hatch reveal, weather chip on a phone, offline Auto-Harvest on a real rejoin) and
the Egg Shop/economy list (shop doesn't close on clicks, drag feel, wheel direction, Left/Right camera
sink, edge-hover auto-scroll, backdrop edges, Gem eggs end to end, real first-rebirth time, mid-session
Lab unlock).

## Open decisions

- **Paying player Rebirth 4** lands day 2; the stated target is day 1. Paying Rebirth 10 is now day 11
  (target ~1 week); free day 23 (target ~3 weeks).
- **Skip Timer pricing** is a soft-launch tuning flag (`Config/Products.lua` comment).
- **Pen income is small by design** (33 h payback); check pinning still feels worth it.
- **Own rank outside the top 100** shows `#100+` (no cheap rank lookup in OrderedDataStore).
- **Still different from DESIGN.md (not in this build):** the daily streak pays eggs and Cash (doc:
  Gems on days 1-6, Toxic egg day 7); the Starter Bundle grants 550 Gems (doc: 500 Gems + 2 Luck
  Potions).
- All pass/product ids and `Game.groupId` are 0 until created in Creator Hub (Studio warns at start).
- `Game.gameLink` is a placeholder (place id 0) until the game is published.

## Next tasks, in order

1. **Before Oct 29 00:00 EDT**: publish with the Pumpkin Egg and do item 7 above in Studio. To test
   before the window opens, temporarily set the Pumpkin's `startsAt` in a local copy of
   `Config/LimitedEggs.lua` to a past time (don't commit it).
2. **Relay go-live**: tools/relay/README.md steps 1-4, then item 1-2 above.
3. **Studio pass** on items 3-6, then the older lists.
4. **Creator Hub setup**: passes, Gem packs, Starter Bundle, the group; fill the ids
   (`Config/Passes.lua`, `Config/Products.lua`, `Config/Game.lua` groupId) until the Studio warning is
   gone; real `gameLink`.
5. **Next limited egg** (Winter): one `Config/LimitedEggs.lua` entry + 10 species in
   `tools/gen-mutants.luau` `LIMITED` (re-run it: it writes `Config/Mutants.lua`). That's all if it
   reuses an existing egg pattern and has no `decor` (the banner is plain config); a new look needs a
   pattern in `MutantModel.buildEgg`, new hub props a `decor` builder in `World.lua`. The generic
   checks in `tests/limited.spec.luau` cover any entry.
6. **M5 remaining**: VIP egg, first-session phone check, icon/thumbnail A/B; daily streak and Starter
   Bundle vs DESIGN.md (decide, then align).

Keep the rules in CLAUDE.md: server-authoritative intents, numbers only in Config, pink only for
spending, HUD below the GuiService inset, previews and checker at 0 issues.
