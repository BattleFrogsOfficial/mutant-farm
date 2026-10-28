# Mutant Farm

A grow-and-mutate idle simulator for Roblox. Plant mutant eggs, let them grow (even offline), sell what hatches, and work toward rarer eggs and rebirths.

Current build: a walled-in valley with 12 fenced farm plots around a hub, 400 collectible mutant species that range from palm-sized to towering giants, six egg designs, mutations that pop while eggs grow, a hatch reveal, a pen full of your best mutants, buyable soil patches, a guided first session, saved data, and an economy simulator for tuning.

## Run it in Studio

You need **Roblox Studio** and **Rojo 7** (the command line tool plus the Rojo Studio plugin).

1. In a terminal, from this folder:
   ```
   rojo serve
   ```
2. Open Studio, create a new **Baseplate** place, then delete the `Baseplate` part and the default `SpawnLocation` in Workspace (the game builds its own map).
3. In the Plugins tab, open **Rojo** and click **Connect**. The scripts appear in ReplicatedStorage, ServerScriptService and StarterPlayerScripts.
4. Press **Play**.

You spawn inside your own farm. Follow the **NEXT UP** box (bottom left) and the green beam: plant, water, hatch, sell, buy eggs, buy a new soil patch.

### Testing saved data

Studio uses a temporary mock save unless the place can reach DataStores:

1. File → **Publish to Roblox** (any name; keep it private).
2. Home → **Game Settings → Security** → turn on **Enable Studio Access to API Services**.
3. Play, earn some Cash, Stop, Play again: Cash, eggs, bag and growing plants should all be there, with growth caught up for the time you were away.

### Game settings to set once published

- **Places → Max Players: 12**. The map has exactly 12 islands.
- Devices: Phone, Tablet, Computer.

## What is Wally (and why you don't need it yet)

Wally is a package manager for Roblox, like npm for JavaScript: you list libraries in a `wally.toml` and `wally install` downloads them into a `Packages` folder. This project only uses two libraries, **Fusion 0.2** (UI) and **ProfileStore** (saving), so they are already committed in `Packages/`. Nothing to install. If we ever need more libraries we can switch to Wally then.

## Developer tools (optional)

These run outside Roblox and are used by Claude Code. Install them with [Rokit](https://github.com/rojo-rbx/rokit) or Cargo if you want to run them yourself:

| Tool | What it's for | Command |
|---|---|---|
| Lune | runs the tests and simulator | `lune run tools/test`, `lune run tools/sim` |
| StyLua | formatting | `stylua src tools tests` |
| Selene | linting | `selene src` |

The simulator plays the game with the real balance numbers and prints when each rebirth is reached. Current result (16 runs, 1.5 active hours per day):

| Rebirth | Cost | Free player | Payer (2x Luck + Auto-Harvest) |
|---|---|---|---|
| 1 | $800K | day 1 (36 min) | day 1 |
| 4 | $140M | day 4 | day 2 |
| 7 | $4B | day 8 | day 5 |
| 10 | $400B | day 21 | day 10 |

## Where things are

- `src/shared/Config/` — every balance number (egg prices, odds, timers, upgrade costs, rebirth costs). Change numbers here only.
- `src/server/` — game logic. The server decides every outcome.
- `src/client/` — UI and visuals.
- `CLAUDE.md` — rules and balance tables for Claude Code.
