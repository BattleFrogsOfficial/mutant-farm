# Mutant Farm — Roblox Game Design & Profit Plan

Design doc. Source of truth for intent and balance targets; synced from the Claude doc on 2026-10-28. CLAUDE.md holds the live numbers.

**Reconciliation (2026-10-28).** The code was brought in line with this doc, and the agreed rule changes were written back here: pen income at 0.05% / 0.01% per minute of base value x the rebirth multiplier, with no offline cap; rebirth sells the bag (outside the pen) first; offline Auto-Harvest catch-up; VIP chat tag and daily Gems (VIP egg stays M5); weather at 120 s with 25 / 30 / 10% per tick, Glitch Storm 1 in 6 and a 5-minute countdown chip; Top Pens and Top Rebirths boards with the viewer's own rank; pins; a server-wide sparkle for every Robux purchase plus chat lines for VIP and the Starter Bundle; the group offer at first sell; the Rebirth Altar; a Studio warning for unlinked product IDs. Still different from this doc and not part of the reconciliation: the daily streak pays eggs and Cash rather than Gems on days 1–6, and the Starter Bundle grants 550 Gems instead of 500 Gems + 2 Luck Potions.

**Rule changes (dated; every rule change lands here and in CLAUDE.md in the same commit).**

- 2026-10-28 — Rebirth costs grow x4.5 per rebirth after the 700K first one (was x5): simulator puts free Rebirth 10 at day 23 and paying at day 11.
- 2026-10-28 — Egg Shop side cards show only the egg art and name; the Gem-mode "2x RARITY ODDS" badge is on the focused card only.
- 2026-10-28 — Weather is one global schedule, a pure function of wall-clock time: an event every 25 minutes (1500 s buckets from the unix epoch, the event 5 minutes into each, 120 s long), its type a seeded hash of the bucket weighted Acid Rain 45% / Solar Flare 40% / Glitch Storm 15% (was: a random event every 20–30 minutes per server, Glitch Storm 1 in 6, the first 6 minutes after a server starts). Announced with toasts at 5:00, 1:00 and the start and a chat line at 5:00; Glitch Storm also goes to Discord at 5:00, posted by exactly one server.
- 2026-10-28 — Limited eggs are a config list (name, design, Gem price, grow time, value tier, odds, species pool, start and end time). On sale only inside their window; the shop shows an active one first, in both Cash and Gems mode, with an "ENDS IN" countdown, and opens on it the first time. Restricted players never see it. After the window owned eggs stay plantable, species stay in the Almanac (marked LIMITED), planted ones survive rebirth. The first is the Pumpkin Egg (Halloween 2026): 600 Gems, 30 minutes, Lab values, Lab's odds with Uncommon and up doubled, 10 Halloween species, Oct 29 00:00 to Nov 5 23:59 New York time; while it runs the Egg Shop gets a banner and the fountain three carved pumpkins.
- 2026-10-28 — Instant Weather (400 Gems): the buyer picks Acid Rain, Solar Flare or Glitch Storm and gets a 120 s event on their plot only, same rolls as global weather and independent of it, never two at once. Offered when no global event is running or due within 5 minutes; hidden and refused where paid random items are restricted.
- 2026-10-28 — Rebirth Now (100 Gems) is offered from 50% of the next rebirth's cost (Rebirth panel and Rebirth Altar sign); it is a normal rebirth (bag sold first, the usual resets) plus the Gems. Not policy-gated (nothing random).
- 2026-10-29 — HUD after the first Studio pass (no gameplay change): the HUD scales with the shorter screen edge (never narrower than the 900-px layout), at most 1.25x with a mouse and 1.0x on touch; panels are sized to their content. Icons are flat vector glyphs in the boxy style, never images. The egg tray shows the eggs you own plus one "next egg" (the cheapest unlocked egg you don't have, with its price, "at the Egg Shop"); locked tiers never appear there (Lab's $25K progress is in the shop and in Next Up). At your plot SHOP is the same size as WATER and sits beside it; in the hub SHOP is the biggest button. WATER says "WATER · 2x 30s", runs a 30-second ring with a "2x" chip on every growing egg, and explains itself once per session. The farm gate shows the live income ("$0/min · plant eggs to earn" before the first harvest). Empty patches show a "+" tile (pulsing during the tutorial's plant step), the next buyable patch its price. The Almanac shows a milestone track instead of a bar: the next reward as a big marker, later ones along the track, a tooltip on tap.

- 2026-10-30 — Gem upgrades (kept through every rebirth, not random, not region-gated), in the Upgrades panel beside the Cash ones: **Pen Slots** +4 mutants in the pen (and pinnable) for 150 Gems, once per rebirth level; **Permanent Luck** +10% luck per level, 3 levels at 200 / 400 / 800 Gems, under the 6x luck cap; **Offline Mutations** +2 h of offline mutation rolls per level, 3 levels at 100 / 200 / 400 Gems (nothing to buy with the Offline Mutations pass). WATER reads "2x GROWTH / FOR 30s" and "2x ACTIVE" with the seconds left while it runs (no drain ring). The farm's $/min (Cash panel, gate sign) counts the expected Cash of the eggs growing now plus the pen, so it is never $0 while eggs grow.

## The pitch

**Mutant Farm** is a grow-and-mutate idle simulator: you plant mutant eggs on your plot, they grow in real time (even while you're offline), random mutations multiply their value, and you sell them for cash to buy rarer eggs, bigger plots, and rebirths. The game is designed around one principle: every system either brings players back or gives them a reason to spend.

**Why this genre.** The grow/idle-with-luck formula (Grow a Garden, Fish It, Kick a Lucky Block) is the dominant money-maker on Roblox in 2026 and the cheapest to build well: no combat, no physics, no maps to design. Its three engines are offline timers (players return on a schedule), random rarity rolls (players pay to roll more), and public trading/showing off (players want the rare thing others can see).

**Why it fits $200.** The whole game is UI, data, and a small plot of land. Art can be low-poly and bright, built from free Toolbox assets and simple meshes. The budget is spent almost entirely on sponsored ads once retention is proven, which is where a $200 budget actually converts to Robux.

**The revenue thesis.** Target break-even (75,000 Robux gross) within 30 days of ad spend, driven by three spend sinks that stack: speed (game passes), luck (dev products), and capacity (plots and slots). Players who don't spend still feed Premium Payouts and fill servers, which makes the game look alive to the players who do.

**Working title:** Mutant Farm. Alternatives if the name is taken: *Grow a Mutant*, *Mutant Garden*. Keep "Grow" or "Farm" in the name — those words are what the target audience searches.

## Core gameplay loop

A full cycle takes 90 seconds in the first session and stretches to hours by day three. The player is always one timer away from a payout and one payout away from a purchase.

1. **Buy eggs** at the Egg Shop with Cash. Each egg type has a rarity table of mutants it can hatch into (Common → Legendary), with rarity rolled at planting and revealed at harvest (full odds per tier in the economy section).
2. **Plant** the egg in a slot on your plot. Plots start at 6 slots and expand to 40.
3. **Grow.** Grow time is set by the egg tier (1 minute to 8 hours), then multiplied by rarity: Uncommon 1.25x, Rare 1.5x, Epic 2x, Legendary 3x — rarer mutants take longer, which is where Skip Timer sells. Growth continues while offline. Watering (one free tap for the whole plot every 30 seconds while present) speeds growth 2x and stacks with the 2x Growth Speed pass for 4x, rewarding active play without punishing idle play.
4. **Mutate.** Every mutant gets exactly 10 mutation rolls per grow, spaced evenly across its grow time, so a Starter egg and a Cosmic egg face the same odds. Each roll checks every mutation independently at its own base chance per roll: Shiny 1.5%, Golden 0.6%, Radioactive 0.25%, Glitched 0.08%, Cosmic 0.01% (about 14%, 6%, 2.5%, 0.8%, 0.1% per egg). Luck multiplies those chances. Mutations multiply each other, each type at most once per mutant (so the ceiling is x250,000): Shiny (x2), Golden (x5), Radioactive (x10), Glitched (x25), Cosmic (x100). Weather events give every growing mutant repeated high chances at one specific mutation for two minutes.
5. **Harvest** when mature. The mutant goes to your inventory, with its mutations and a generated size value (size is a second multiplier, 0.8x to 3x).
6. **Sell** at the Sell Pad, or **Keep** in your display pen where other players on the server can see it. The pen auto-fills with your most valuable mutants, and any mutant can be pinned to stay there (from the bag or the hatch reveal; pins are capped at the pen's size, Sell All skips them, and a pinned mutant is never auto-replaced or auto-sold on rebirth; unpinning returns it to the bag). Kept mutants also generate passive Cash per minute, so keeping rare ones is both a flex and an income choice.
7. **Upgrade**: more slots, faster growth, better mutation odds, a bigger pen.
8. **Rebirth** at a Cash threshold: reset Cash, slots and eggs; keep display pen and game passes; gain a permanent multiplier and unlock the next egg tier. Each rebirth makes the loop faster and the numbers bigger, which keeps the sense of progress alive for weeks.

**Why the loop is shaped this way (profit view).** Timers create return visits. Mutation rolls create a slot-machine moment the player can buy more of. The display pen turns rare mutants into social proof, so a whale's spend advertises the game to everyone else in the server. Rebirth resets the spend pressure without resetting the player's investment.

**Stealing (v2, not v1).** A "Raid" mode where players can steal unprotected mutants from others' pens is what drives the Steal a Brainrot economy (locks and shields sell). It is held for v2 because it is a grief risk and a moderation burden until the core loop proves retention.

## Progression & economy math

One currency (Cash) and one premium currency (Gems). Cash is earned in-game and inflates with rebirths; Gems are bought with Robux or earned in small daily drips, and buy luck, speed, and skips. Two currencies let the free loop stay generous while the premium loop stays scarce.

**Egg tiers.** Tiers are gated by rebirth count (Lab by total Cash earned instead, so there are three eggs before the first rebirth), and the shop always shows the next locked tier with a progress bar rather than a padlock.

| Tier | Unlock | Egg cost (Cash) | Grow time | Base sell value | Legendary odds |
| --- | --- | --- | --- | --- | --- |
| Starter | Rebirth 0 | 50 | 1 min | 80 | 1 in 2,000 |
| Swamp | Rebirth 0 | 500 | 5 min | 900 | 1 in 1,500 |
| Lab | Rebirth 0, after $25K total earned | 5,000 | 20 min | 11,000 | 1 in 1,000 |
| Toxic | Rebirth 1 | 50,000 | 1 hr | 130,000 | 1 in 800 |
| Void | Rebirth 3 | 500,000 | 3 hr | 1.6M | 1 in 500 |
| Cosmic | Rebirth 6 | 5M | 8 hr | 20M | 1 in 300 |
| (v1.5) seventh tier | Rebirth 10 | — | — | — | — |

**Rarity odds per tier (%).** Rarity is rolled at planting (so a Luck Potion must be active when the egg goes in) and revealed at harvest. Luck multiplies the Uncommon-and-above weights, then all five weights are renormalized to sum to 100%, so no luck level can overflow. Total luck is capped at 6x (pass x potion). Implement as percentages, not 1-in-N.

| Tier | Common | Uncommon | Rare | Epic | Legendary |
| --- | --- | --- | --- | --- | --- |
| Starter | 80 | 15 | 4.45 | 0.5 | 0.05 |
| Swamp | 75 | 18 | 6 | 0.93 | 0.07 |
| Lab | 70 | 20 | 8 | 1.9 | 0.1 |
| Toxic | 65 | 22 | 10 | 2.875 | 0.125 |
| Void | 60 | 24 | 12 | 3.8 | 0.2 |
| Cosmic | 55 | 25 | 14 | 5.67 | 0.33 |

Sell values are the Common outcome; rarity multiplies them (Uncommon x3, Rare x10, Epic x40, Legendary x250), then mutations, then size. A Golden Legendary Toxic mutant is worth about 160M Cash — a number that gets screenshotted.

**Pacing targets.** These are the numbers to tune toward in the soft launch; they produce spend pressure without a paywall.

- First Rare hatch: within 5 minutes of first play (scripted: the second egg is guaranteed Rare).
- First rebirth: 35–45 minutes of active play on day one.
- Rebirth 3 (Void tier): day 3–4 for a free player, day 1 for a player with 2x Luck + Auto-Harvest.
- Rebirth 10: about 3 weeks free, 1 week paying. Rebirth 1 costs 700,000 Cash with Lab at $5,000, which the simulator puts at about 25 minutes for a perfect player and real players at roughly 33–40 — the target, because the first rebirth is the tutorial for the whole meta. The Lab price is never the tuning lever (above \~$30K players skip it). From Rebirth 2 on, each costs 4.5x the previous (3.15M, 14.2M, …; was 5x until 2026-10-28, see the notes at the top) under the rule that it takes about 90 minutes of active earnings at full slots on the best tier that rebirth has unlocked; the M1 simulator sets the final table. Each rebirth adds a permanent +50% Cash multiplier, additive (Rebirth 4 = 3x, Rebirth 10 = 6x).

**Where the friction lives.** Friction is placed only where a product removes it: slots fill up (buy slots), growth is slow (buy speed), Legendaries are rare (buy luck), and you are away from the keyboard (buy auto-harvest and offline bonus). Nothing else should ever feel slow.

**Passive income from the pen.** Each kept mutant pays 0.05% of its *base* value (tier x rarity, no mutations or size) per minute online and 0.01% offline, scaled by the rebirth multiplier. That is a 33-hour payback online, so selling stays the right call for most hatches, keeping the rarest is still worthwhile, and the pen never short-circuits a rebirth threshold. Offline income has no time cap (the rate itself is the limit). Pen starts at 8 slots; pen slots are sold in v1.5.

**Cash upgrades (`Upgrades.lua`).** Slots 7–40 start at 200 Cash and each next slot costs 1.5x the last. Growth Speed and Mutation Odds upgrades have 5 levels each (+10% per level), starting at 2,000 Cash and tripling per level. All upgrade costs scale with the rebirth count so they stay relevant after a reset.

**Gem upgrades (`Upgrades.lua`, kept through rebirth).** Pen Slots: +4 pen mutants for 150 Gems, once per rebirth level. Permanent Luck: +10% luck per level, 3 levels (200 / 400 / 800 Gems), under the 6x cap. Offline Mutations: +2 h of offline rolls per level, 3 levels (100 / 200 / 400 Gems); maxed by the Offline Mutations pass.

**Other rules**

- Auto-Harvest replants the same egg, paying from Cash, keeps working offline, and stops when the player cannot afford the next egg. Offline it is replayed at rejoin, cycle by cycle (mature → harvest to the bag → replant if Cash allows and the bag has room); mutation rolls on those cycles obey the 2-hour offline cap unless Offline Mutations is owned.
- Size is rolled from bands: 0.8–1.0x (25%), 1.0–1.3x (55%), 1.3–2.0x (17%), 2.0–2.9x (2.5%), 3.0x "Titan" (0.5%). Luck multiplies the top two bands' weights, then weights renormalize.
- VIP's 1.5x Cash and the rebirth multiplier multiply each other.
- On rebirth, unsold inventory (everything outside the pen) is sold automatically first, at full value through the economy service so it is logged and counted as Cash earned; then Cash, slots, upgrades and eggs reset. The pen (pinned mutants included), passes, Gems and streak are kept.
- The day-7 streak Toxic egg is granted regardless of rebirth count, as a taste of the next tier.

## Retention systems

The game needs players to come back on day 1, 3, and 7 before any ad money is spent. Each system below targets one of those return points.

- **Offline growth with a cap.** Mutants keep growing offline, but mutation rolls stop after 2 hours away unless the player owns the Offline Mutations pass. The cap creates the itch to log in; the pass sells the relief.
- **Weather events** every 25 minutes on one global schedule (every server runs the same event at the same moment), announced with a countdown (a chip on every player's HUD from 5 minutes before, toasts at 5:00, 1:00 and the start, a chat line at 5:00): *Acid Rain (Radioactive, 45% of events), Solar Flare (Golden, 40%), Glitch Storm (Glitched, the rare one: 15%). Each event lasts 120 s with a roll every 30 s on every growing egg: 25% / 30% / 10% per tick, so about 68% / 76% / 34% of eggs that grow through the whole event get the mutation. Not a force-roll; the economy stays tunable.* Events are the day-3 hook — players learn they happen and leave the game open or come back for them. A Discord webhook posts "Glitch Storm in 5 min" to a community channel (one post per storm, through a small relay, since Roblox can't call Discord directly).
- **Daily login streak**: Gems on days 1–6, a free Toxic egg on day 7, resets on a miss. Cheap to build, proven, feeds the Gem economy.
- **Session goals**: a "Next up" panel always shows the nearest unlock (next slot, next rebirth, next egg tier) with a progress bar. Players quit when they don't know what's next.
- **Leaderboards: leaderstats (Rebirths, Cash) in the player list, plus two global top-100 boards side by side at the north edge of the plaza, Top Pens (current pen value) and Top Rebirths, refreshed every 120 s, each showing the viewer's own rank at the bottom (as "#100+" outside the top 100).** Being on the board is the free-player status loop; staying on it is the whale loop.
- **Limited-time eggs** rotated weekly after launch (a holiday egg for Halloween week, then a Winter egg). Exclusivity is the strongest spend trigger in the genre; the limited egg should always be purchasable with Gems. Egg count grows on a cadence, not at launch: a limited egg every week, a permanent tier every 3–4 weeks (the seventh tier at Rebirth 10 is the first), and a Gem variant of each tier from launch (same species and values, Uncommon+ weights doubled then renormalized, policy-gated; 15 / 40 / 120 / 300 / 800 / 2,000 Gems by tier) that doubles the catalog at near-zero art cost.
- **Group Reward.** No promo codes in this game. The free community lever is a Group Reward instead: members of the Roblox group get +10% Cash for as long as they stay in it (checked on every join with IsInGroup), shown as a badge on the Cash panel, plus 2 Swamp Eggs once as the hook. Offered once at first sell with a prompt: "Join the group for +10% Cash forever (+2 Swamp Eggs now)". A player who joins mid-session gets the bonus on their next sell.
- **Almanac milestones.** The 400 species are cosmetic within a rarity, so the Almanac is the collection goal: 25 Gems every 25 species, plus a Toxic egg at 100, a Void egg at 200, a Cosmic egg at 300, and permanent +10% luck at 400. No cosmetic rewards in v1.
- **Trading (v1.5).** Player-to-player trading of mutants once there are enough players for a market. Trading makes rares feel like assets, which raises how much players will pay to get them.

## Monetization catalog

Every product removes a friction the loop deliberately creates. Prices follow the Roblox convention of 99/249/499/999 — buyers have mental anchors at those points and odd prices read as suspicious. Game passes are the floor (one-time, high conversion); dev products are the ceiling (repeatable, where 5% of players produce 70% of revenue).

**Game passes (one-time, permanent)**

| Pass | Price (Robux) | What it does | Why it sells |
| --- | --- | --- | --- |
| 2x Luck | 399 | Doubles rarity and mutation odds | The best-converting pass in the genre; promoted on the egg shop itself |
| Auto-Harvest | 249 | Harvests mature mutants and replants the same egg | Removes the most repetitive click; sells to everyone who plays past day 2 |
| 2x Growth Speed | 299 | Halves all grow timers | Stacks visibly with watering; shown on every timer bar |
| Offline Mutations | 199 | Mutation rolls continue while offline, no 2-hour cap | Sells at the exact moment the player sees the cap message |
| +10 Plot Slots | 349 | Ten permanent extra slots | Capacity is the clearest "I'd earn more if" feeling |
| VIP | 499 | Gold "[VIP]" chat tag, 1.5x Cash, 50 Gems a day (claimed from a VIP strip on the Daily panel), and (M5) a VIP egg with an exclusive species pool | Status pass; the chat tag is advertising in every server |
| Starter Bundle | 599 | 2x Luck + Auto-Harvest + 500 Gems + 2 Luck Potions, offered once in the first 10 minutes and never again (the scarcity is the product) | Anchors the shop; about 32% off the 875-Robux list value |

**Developer products (repeatable)**

| Product | Price (Robux) | What it does | Why it sells |
| --- | --- | --- | --- |
| 100 Gems | 49 | Entry pack | Low-friction first purchase; the goal is the first buy, not the amount |
| 550 Gems | 199 | Standard pack | Best-value tag at this tier |
| 1,500 Gems | 499 | Big pack | Whales buy this repeatedly for limited eggs |
| 4,000 Gems | 999 | Mega pack | Top anchor that makes 499 look reasonable |
| Luck Potion (30 min, x3 luck) | 25 Gems | Stacks with the 2x pass | The slot-machine lever; sold inside the hatch screen |
| Skip Timer | 5 Gems per 10 min remaining | Finish growing now | Converts impatience directly |
| Instant Weather | 400 Gems | Trigger a chosen weather event on your plot only | The whale product; priced where a free player can see it and a payer can afford it weekly |
| Rebirth Now | 100 Gems | Rebirth without meeting the Cash threshold, offered from 50% of it (Rebirth panel and Rebirth Altar) | Sells at the moment the player is 80% there |
| Limited egg | 500–1,500 Gems | The weekly rotating egg (first: Pumpkin Egg, 600 Gems, Oct 29 – Nov 5 2026) | Exclusivity; the single biggest revenue line after month one |

**Placement rules for Claude Code**

- A buy prompt appears only at the moment of friction: slots full → +10 Slots; 2-hour offline cap message → Offline Mutations; timer over 10 minutes → Skip Timer; opening any egg → Luck Potion and 2x Luck.
- One prompt per friction, never a pop-up on join. Join-time pop-ups raise day-1 bounce, which costs more than they earn.
- The shop is one screen with passes on top and Gems below, with the Starter Bundle shown first for new players with a 10-minute countdown.
- Every purchase triggers a visible server-wide effect (a sparkle on the buyer's plot, a chat line for VIP and bundle buys). Spending that others see produces more spending.

**Premium Payouts.** No work required beyond session length: Roblox pays creators from Premium subscribers' engagement time. Target average session over 12 minutes; the weather countdown and watering loop are tuned for this.

**Gem exchange sanity check.** At the 100-for-49 entry pack a Gem is about 0.5 Robux, so Luck Potion ≈ 12 Robux, Skip Timer ≈ 2.5 Robux per 10 min, Rebirth Now ≈ 50 Robux, Instant Weather ≈ 200 Robux, limited eggs ≈ 250–750 Robux. Whales buy the 999 pack, where a Gem is 0.25 Robux, which is the intended discount for volume.

**Paid-random-item policy.** Roblox requires odds to be shown for any random item bought directly or indirectly with Robux, and some countries restrict paid random items entirely. Rules: every egg shows its odds panel (the table above) before purchase; on join the server checks `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` and, when true, hides Gem-purchasable eggs and the Luck Potion for that player. The 2x Luck pass stays (it modifies Cash eggs, which are free to obtain) but should be re-checked against current policy text before launch.

**Ownership and IDs.** The game is published under your personal account for v1 (DevEx goes to one verified account, no group payout split to configure); move it to a group only if a partner joins. `Passes.lua` and `Products.lua` hold placeholder IDs (0) until the items are created in Creator Hub; Studio test purchases work with placeholders, and Studio's output lists every pass and product still at 0 on startup so nothing ships unlinked.

## Look & feel

Bright, low-poly, slightly gross. The art direction is "cute science accident": toxic greens and purples against a clean cream sky, chunky rounded shapes, and mutants that are blobby creatures with one exaggerated feature (three eyes, a giant tooth, antennae). Everything reads on a phone screen at thumbnail size, because most of the audience plays on mobile.

**Palette.** Base: toxic green `#7CFF4A`, lab purple `#9B5CFF`, cream `#FFF4D6`, dark slate UI `#1E2230`. Mutation glows are the only saturated accents: Shiny white, Golden `#FFD24A`, Radioactive green, Glitched magenta/cyan flicker, Cosmic deep purple with stars. Rarity colors follow the platform convention (grey, green, blue, purple, gold) so players already know what they mean.

**World.** One small island per player (their plot and pen) arranged in a ring around a central hub with the Egg Shop, Sell Pad, Rebirth Altar, and the global leaderboards. The Rebirth Altar is a glowing pad on the plaza's south edge, across the fountain from the boards, with a sign showing "Rebirth N · $cost · unlocks <next tier>" and a progress bar; stepping on it opens the Rebirth confirm panel. Servers hold 12 players so pens are visible and the hub feels busy. No terrain to design beyond the ring.

**Mutants.** Built in code from Roblox primitives and free Toolbox meshes (blob, spiky, tall, flat), recolored and scaled per rarity, with mutation effects as particle emitters and surface materials. This gives 6 tiers x 5 rarities = 30 mutants from about 8 meshes, and every mutation is a shader change rather than new art.

**UI.** Big chunky boxy buttons (square corners, ink outlines, hard shadows; players asked for it), one font (Fredoka or the Roblox default Builder Sans Bold), numbers formatted with suffixes (1.2K, 4.5M). Timer bars on every slot. The "Next up" panel is pinned bottom-left. Shop buttons are always one tap away on the right edge. The HUD never shares the top-bar strip with Roblox's own buttons: it sits below \`GuiService:GetGuiInset()\`, with the chat window moved to the bottom-left at its smallest size. Robux prices are shown with the Robux icon, never hidden behind a menu.

**Sound.** Hatch jingle that scales with rarity (Common is a pop, Legendary is a 2-second fanfare with screen shake), a wet squelch on harvest, cash register on sell, a siren for weather. Rarity-scaled sound is the cheapest dopamine in the game.

**Icon and thumbnail.** The icon is one Legendary mutant with a Golden glow, mouth open, on a toxic green background with the title in fat white letters. Thumbnails: (1) a plot with a Cosmic mutant mid-mutation and a big "x100" callout, (2) a weather event with the countdown, (3) a before/after "Rebirth 10" pen. Run two icon variants against each other in the first ad tranche and keep the winner; icon click-through rate is the single biggest driver of ad cost.

**Asset ownership.** Claude Code builds all v1 mutants, effects, and UI from primitives, free Toolbox asset IDs, and Roblox's free sound library, with every asset ID in one `Assets.lua` config so real art can be swapped in later without touching code. Claude Code drafts the 30 mutant names and their exaggerated feature in `Mutants.lua` for you to edit. The icon and thumbnails are the one commissioned item in the budget.

## Technical architecture (for Claude Code)

Server-authoritative Luau with Rojo so the whole game lives in a Git repo Claude Code can edit. The client only renders and sends intents; every number that touches money is computed on the server.

**Tooling**

- Rojo 7 project (`default.project.json`) syncing `src/` into Studio; Wally for packages; Selene + StyLua for lint and format.
- Packages: ProfileStore (session-locked player data, the standard for games with real money), Knit or a lightweight service pattern, Promise, Signal.
- Data in `ReplicatedStorage/Config` as plain Luau tables: `Eggs.lua`, `Mutations.lua`, `Passes.lua`, `Products.lua`, `Weather.lua`. All balance numbers live here so tuning never touches logic.

**Folder layout**

```
src/
  server/
    Services/   PlotService, GrowthService, MutationService, EconomyService,
                ShopService, RebirthService, WeatherService, DataService,
                LeaderboardService
    Main.server.lua
  client/
    Controllers/ UIController, PlotController, ShopController, EffectsController
    UI/          Fusion or plain ScreenGui modules per screen
  shared/
    Config/      balance tables
    Types.lua, Remotes.lua, Format.lua (number suffixes), Rng.lua (seeded rolls)
```

**Core services**

- **DataService** wraps ProfileStore. Profile template: cash, gems, rebirths, slots, pen, inventory, ownedPasses, lastSeen, streak, inGroup, stats. Save on leave and every 2 minutes; BindToClose flushes.
- **GrowthService** does no per-frame work. Each slot stores `plantedAt`, `eggId`, `mutations[]`, `lastRollAt`. On join and every 60 seconds the server computes elapsed time, applies growth and the number of mutation rolls owed (capped at 2 hours offline unless the pass is owned), and replicates the result. Offline progress is a pure function of timestamps, which makes it cheap and exploit-proof.
- **MutationService** owns the roll. One `Rng.roll(seed, luckMultiplier)` path used for rarity, mutations, and size so a luck change affects everything at once.
- **EconomyService** is the only writer of cash and gems. Every sell, buy, and reward goes through it and is logged.
- **ShopService** handles `MarketplaceService.ProcessReceipt` for dev products (idempotent on `PurchaseId`, stored in the profile so a rejoin never double-grants) and `UserOwnsGamePassAsync` with a cached result per session. Grant passes on `PromptGamePassPurchaseFinished` too so the effect is immediate.
- **WeatherService** runs a per-server schedule, broadcasts the countdown, and applies the forced mutation through MutationService. It also fires the Discord webhook (via HttpService on a proxy) 5 minutes before Glitch Storm.
- **RebirthService** validates the threshold, resets the right fields, bumps the multiplier.
- **LeaderboardService** uses OrderedDataStore, refreshed every 120 seconds, with pen value and rebirths as two stores.

**Anti-exploit**

- Clients never send values, only intents (`Plant(slotIndex, eggId)`, `Harvest(slotIndex)`, `Sell(itemId)`). The server re-derives everything.
- Rate-limit remotes per player (10 calls/second) and reject out-of-range indices silently.
- Server-side sanity checks on cash deltas (no single transaction may exceed the theoretical max for the player's tier).

**Analytics.** Use Roblox's built-in Analytics (Economy events for every source and sink, Funnel events for the first-session steps: plant → first hatch → first sell → first rebirth → first purchase prompt). This funnel is what the soft-launch decisions in the launch section are made from.

**Resolved design decisions**

- The M1 profile template already stores rarity, mutations, and size per slot and per inventory item, unused until M2, so no data migration is ever needed.
- Rarity is rolled at planting and stored on the slot; mutation rolls use the luck multiplier active at each roll. The Luck Potion therefore matters at planting *and* while growing, which is intended.
- Grow time = tier time x rarity multiplier x 1/(watering 2x) x 1/(pass 2x). Watering is one tap for the whole plot.
- Pen income is computed from base value only, in the same timestamp-driven pass as growth.
- A player's plot rebuilds from saved data on whatever island they get in any server. Visitors can walk onto any island and look; no interaction with others' plots until Raid mode in v2.
- Discord cannot be called from Roblox servers directly; the weather webhook goes through a free Cloudflare Worker relay (one endpoint, one secret). Build it in M5, not before.

## Build order

Ship the smallest game that can prove retention, then add the systems that monetize it. Each milestone ends with a playable build; nothing in a later milestone is started until the earlier one is in players' hands.

| Milestone | Scope | Done when | Target |
| --- | --- | --- | --- |
| M1 — Skeleton | Rojo repo, ProfileStore, plot with 6 slots, Starter + Swamp eggs, grow timers, harvest, sell, Cash HUD, and a headless economy simulator (\`tools/sim.lua\`) that plays the loop at a given rebirth and prints Cash/min and time to the next rebirth | A new player can plant, wait, harvest, and sell, and their data survives a rejoin | Week 1 |
| M2 — The hook | Rarity rolls, 5 mutations with effects, size, hatch animation + sounds, display pen, "Next up" panel, offline growth | A tester screenshots a Golden Rare unprompted | Week 2 |
| M3 — Monetize | All 7 game passes, Gem products, Luck Potion, Skip Timer, Starter Bundle timer, purchase effects, placement rules | Every product can be bought and tested in Studio with test purchases | Week 3 |
| M4 — Return loops | Rebirth, Lab + Toxic tiers, weather events, daily streak, server + global leaderboards, group reward | Day-1 and day-3 testers come back without being asked | Week 4 |
| Soft launch | Unlisted, 20–50 players from friends and small communities, analytics funnel on | Day-1 retention over 25% and median session over 10 min | Week 5 |
| M5 — Scale | Void + Cosmic tiers, Instant Weather, Rebirth Now, limited egg #1, icon/thumbnail A/B, Discord webhook | First paid ad tranche live | Week 6 |
| v1.5 | Trading, pen slots as a product | Daily actives over 300 | Week 8+ |
| v2 | Raid mode with locks and shields as products | Only if v1.5 holds | Later |

**Scope rules.** No cosmetics, no quests, no pets as a separate system, no map beyond the hub ring in v1. Each of those is a week of work that doesn't move retention before the loop is proven. Mutants in the pen already serve as pets and cosmetics.

**Claude Code handoff.** Start Claude Code with this document and the folder layout above, and ask it to build M1 as a single pull request with a `CLAUDE.md` that records the balance tables, naming conventions, and the server-authoritative rule. Then one PR per milestone.

## Launch & marketing playbook

The $200 is spent in gated tranches, and no tranche is released until the previous one earned back at least half its cost in Robux. Ads multiply a game that retains; they do nothing for one that doesn't.

**Budget**

| Line | Amount | When |
| --- | --- | --- |
| Icon + thumbnail (commission or a few hours in Blender/Studio) | $30 | Week 5, before soft launch |
| Ad tranche 1 — icon A/B, 2 variants | $30 | After soft-launch gate |
| Ad tranche 2 — winning icon, broad targeting | $40 | If tranche 1 earned ≥ $15 in Robux |
| Ad tranche 3 — timed to limited egg #1 | $60 | If tranche 2 ROAS ≥ 0.8 |
| Reserve (ad burst or a plugin/sound pack) | $40 | Held |

**Soft launch gates (week 5).** Read these from Creator Hub analytics after 7 days with 30+ unique players:

- Day-1 retention over 25% and day-7 over 8%. Below that, fix the first 10 minutes before spending anything.
- Median session over 10 minutes. Below that, the weather timer and "Next up" panel need tuning.
- Funnel: over 70% of players reach first sell, over 40% reach first rebirth, over 60% see at least one purchase prompt.
- At least one organic purchase from a non-friend. That proves the shop placement works before it is scaled.

**Free channels (do these before and alongside ads)**

- Roblox group with the game pinned; a Discord with the weather webhook. The group is also how DevEx-eligible community features (group funds) work later.
- Send an early-access link to 20 small Roblox YouTubers/TikTokers (1k–50k subscribers) who cover simulator games, and offer their name on a Creators board in the hub. Small creators say yes to free exclusivity; large ones ignore cold outreach.
- Three short vertical clips: a Legendary hatch with the fanfare, a Glitch Storm, and a "my pen is worth 2B" tour. Post on TikTok and YouTube Shorts with the game name in the caption.
- Your marketing agency's existing accounts and skills apply directly here; treat the game as a client with a $200 media budget.

**Ad mechanics**

- Use Roblox sponsored experience ads (Creator Hub → Ads Manager), bid on cost per play, mobile-heavy targeting, the youngest age band Ads Manager currently allows (check the minimum before tranche 1 — under-13 targeting may be restricted), US first, then broaden.
- Always run two creatives against each other; kill the loser after 24 hours.
- Schedule tranches to start Friday afternoon US time, when concurrent players peak and servers fill fastest.

**KPIs to watch daily**: concurrent players, day-1 retention, Robux per daily active user, purchase conversion rate by product, and cost per play from ads. Robux per DAU above 2 is the signal to keep buying ads.

## Revenue projections & decision rules

At the standard DevEx rate of $0.0038 per Robux and Roblox's 30% marketplace cut, $200 back requires about 75,000 Robux of gross sales. Spend from age-verified US adults pays a higher $0.0054 tier, but the core audience is younger, so plan on the standard rate.

| Scenario | Avg. concurrent players | Robux / DAU | Monthly gross Robux | Monthly USD (after cut, DevEx) |
| --- | --- | --- | --- | --- |
| Flop | 5 | 0.5 | 4,000 | $11 |
| Small win | 40 | 2 | 130,000 | $345 |
| Solid | 150 | 3 | 700,000 | $1,860 |
| Breakout | 800 | 4 | 5,000,000 | $13,300 |

DAU is roughly concurrent players x 30 for this genre. The "Small win" row is the realistic target for a $200 first launch and already clears the budget in month one; everything above it comes from the limited-egg cadence and trading holding players for months.

**Decision rules**

- **Kill** if, after tranche 2, day-1 retention is still under 20% or Robux per DAU is under 1. Stop spending, keep the game live (it costs nothing), and reuse the codebase for the next concept — the services, shop, and data layer transfer to any simulator.
- **Hold** if retention passes but Robux per DAU is 1–2: the loop works, the shop doesn't. Reposition prompts, re-price, add the limited egg, retest with $20.
- **Scale** if Robux per DAU is over 2 and ad ROAS is over 1: reinvest 50% of DevEx-able earnings into ads monthly, ship a limited egg every week, and start v1.5.

**Cash-out requirements.** DevEx needs an age-verified account, Roblox Premium at the time of the request, a minimum of 30,000 earned Robux, and one request per month. Buy the cheapest Premium tier before the first cash-out and treat it as a cost of doing business.

Sources: [Roblox newsroom — DevEx rate increase for 18+ US players](https://about.roblox.com/newsroom/2026/04/roblox-fuels-high-fidelity-games-over-18-players-increases-qualifying-devex-rate-42), [Robux to USD calculator with current DevEx rates](https://generalistprogrammer.com/tools/robux-to-usd-calculator), [Most popular Roblox games right now](https://rowatcher.com/news/the-most-popular-roblox-games-right-now-ranked-by-live-players).
