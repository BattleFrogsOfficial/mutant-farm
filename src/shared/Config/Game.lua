--!strict
-- Global tuning that doesn't belong to a single system.

return {
	-- New player
	startingCash = 100,
	startingEggs = { Starter = 2 },

	-- Watering: one tap waters the whole plot for `waterDuration` seconds at `waterMultiplier` speed.
	waterDuration = 30,
	waterMultiplier = 2,

	-- Luck (pass x potion) is capped here before it touches any roll.
	maxLuck = 6,

	-- Offline: mutation rolls stop this long after the player leaves (unless Offline Mutations is owned).
	offlineMutationCap = 2 * 60 * 60,

	-- Inventory / pen
	inventoryCap = 200,
	penSlots = 8,
	penIncomePerMinuteOnline = 0.0005, -- fraction of base value (tier x rarity)
	penIncomePerMinuteOffline = 0.0001,

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
}
