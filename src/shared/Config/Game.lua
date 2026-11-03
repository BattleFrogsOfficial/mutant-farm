--!strict
-- Global tuning that doesn't belong to a single system.

return {
	-- New player
	startingCash = 100,
	startingEggs = { Starter = 2 },

	-- Watering (shared/Watering.lua, WaterService). Standing on your plot's water pad grows the
	-- whole plot at `padMultiplier` for as long as you stand there (the server checks your
	-- position every `padPollSeconds`; `padTolerance` studs past the pad's edge still count). The
	-- growth circle on the HUD offers a boost: tap it and the plot grows at the offered multiplier
	-- for `tapSeconds` (the higher of the boost and the pad applies, they don't multiply), then a
	-- new offer appears somewhere else on the screen. Offers are rolled by the server from
	-- `tapOffers` ({ multiplier, weight }; lower is likelier: 3x 30%, 4x 22%, 5x 16%, 6x 11%, 7x 8%,
	-- 8x 6%, 9x 4%, 10x 3%, 4.94x on average). A tap up to `tapGrace` s early (latency) still counts.
	-- Both stack with the 2x Growth Speed pass and the Growth Speed upgrade. Nothing runs offline.
	water = {
		padMultiplier = 2,
		padPollSeconds = 0.25,
		padTolerance = 0.5,
		tapSeconds = 5,
		tapGrace = 0.3,
		tapOffers = {
			{ 3, 30 },
			{ 4, 22 },
			{ 5, 16 },
			{ 6, 11 },
			{ 7, 8 },
			{ 8, 6 },
			{ 9, 4 },
			{ 10, 3 },
		},
	},

	-- Luck (pass x potion) is capped here before it touches any roll.
	maxLuck = 6,

	-- Offline: mutation rolls stop this long after the player leaves (unless Offline Mutations is owned).
	offlineMutationCap = 2 * 60 * 60,

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
