--!strict
-- Global tuning that doesn't belong to a single system.

return {
	-- New player
	startingCash = 100,
	startingEggs = { Starter = 2 },

	-- Watering (shared/Watering.lua, WaterService). Standing on your plot's water pad grows the
	-- whole plot at `padMultiplier` for as long as you stand there (the server checks your
	-- position every `padPollSeconds`; `padTolerance` studs past the pad's edge still count). The
	-- growth circle on the HUD (only while you stand on the pad and an egg grows) offers a boost: tap it
	-- and the plot grows at the offered multiplier for `boostSeconds` (the higher of the boost and
	-- the pad applies, they don't multiply). Then the circle vanishes for a gap the server rolls
	-- uniformly in [gapMin, gapMax] seconds and comes back somewhere else with a new offer.
	-- Offers are rolled by the server from `tapOffers` ({ multiplier, weight }: 2x 30%, 3x 30%,
	-- 4x 20%, 5x 12%, 7x 5%, 10x 3%, 3.55x on average; 2026-11-05). A tap up to `tapGrace` s early
	-- (latency) still counts. Both stack with the Growth Speed pass and the Growth Speed upgrade.
	-- Off the pad neither the circle nor a running boost counts (1x). Nothing runs offline. With a
	-- perfect tapper the pad + circle cycle is ~2.7x.
	water = {
		padMultiplier = 2,
		padPollSeconds = 0.25,
		padTolerance = 0.5,
		boostSeconds = 5,
		gapMin = 3,
		gapMax = 8,
		tapGrace = 0.3,
		tapOffers = {
			{ 2, 30 },
			{ 3, 30 },
			{ 4, 20 },
			{ 5, 12 },
			{ 7, 5 },
			{ 10, 3 },
		},
	},

	-- Game passes while testing in Studio. Off: every Studio session starts with no passes (the
	-- place's creator "owns" every pass, and Studio test purchases would otherwise stick), so you
	-- test the free game; a pass test-bought in the session works until you stop. Live servers
	-- always check real ownership on join. Turn on to test with the passes you own.
	studioPasses = false,

	-- Luck (pass x potion) is capped here before it touches any roll.
	maxLuck = 6,

	-- Offline: mutation rolls stop this long after the player leaves (unless Offline Mutations is owned).
	offlineMutationCap = 2 * 60 * 60,
	-- Offline mutation rolls happen at this share of the online chance (2026-11-04).
	offlineMutationChanceScale = 0.25,

	-- Auto-Harvest pass: a mature egg of this rarity is sold the moment it's hatched (never kept);
	-- the rest go to the bag. Offline, the pass replays at most this many hours after you leave.
	autoSellRarity = "Common",
	autoHarvestOfflineHours = 8,

	-- Inventory / pen
	inventoryCap = 200,
	penSlots = 8,
	-- Pen income: every mutant standing in your pen pays this fraction of its base value
	-- (tier x rarity only: size and mutations only boost the sale price) per minute, times the
	-- rebirth multiplier, paid every payoutSeconds while online. A plain size-1 mutant pays back
	-- its sell value in 1 / 0.0005 = 2,000 min (~33 h) online. Offline it earns at
	-- penIncomePerMinuteOffline for the whole time away (paid at join), with no cap.
	penIncomePerMinute = 0.0005,
	penIncomePerMinuteOffline = 0.0001,
	payoutSeconds = 60,

	-- World
	islandCount = 12,
	maxPlayers = 12,

	-- Networking
	remoteCallsPerSecond = 10,
	stateFlushInterval = 0.1,

	-- Data
	autoSaveSeconds = 120,
	-- Server settles online plots this often so mid-grow mutations show up promptly.
	growthTickSeconds = 5,

	-- Pen shows the owner's most valuable mutants from their bag.
	penDisplayCount = 8,

	-- Group: members get +groupCashBonus Cash for as long as they're in the group (checked on join
	-- and when they tap Claim), plus the one-time eggs. Set groupId to your group's id (0 = off).
	groupId = 0,
	groupCashBonus = 0.1,
	groupReward = { eggs = { Swamp = 2 } },

	-- Almanac milestones: every `every` species discovered pays `gems` Gems, and the big ones in
	-- `big` pay real goods instead (eggs; `luck` is a permanent luck multiplier bonus).
	almanacMilestones = {
		every = 25,
		gems = 25,
		big = {
			[100] = { eggs = { Toxic = 1 } },
			[200] = { eggs = { Void = 1 } },
			[300] = { eggs = { Cosmic = 1 } },
			[400] = { luck = 0.1 },
			[500] = { gems = 100 }, -- the 500-species roster's top milestone (no more luck)
			[600] = { eggs = { Magma = 1 } }, -- with Magma and Quantum (2026-11-03): 676 species
			[675] = { gems = 200 },
		},
	},

	-- Global boards in the hub (Top Pens, Top Rebirths; OrderedDataStores): how often online
	-- players' values are saved and the top 100 re-read and sent to clients.
	leaderboardSeconds = 120,

	-- Discord weather relay (tools/relay, a Cloudflare Worker): Glitch Storm is posted there at
	-- T-5:00 by one server. "" = off. The key is the Roblox secret WEATHER_RELAY_KEY.
	relayUrl = "",
	gameLink = "https://www.roblox.com/games/0/Mutant-Farm", -- put the real place id here
}
