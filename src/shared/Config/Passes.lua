--!strict
-- Game passes (one-time). Replace id = 0 with the real IDs from Creator Hub.
-- Wired up in M3.

return {
	Luck2x = { id = 2066646427, price = 399, name = "2x Luck", description = "Doubles rarity and mutation odds" },
	AutoHarvest = {
		id = 2067408399,
		price = 249,
		name = "Auto-Harvest",
		description = "Hatches ripe eggs, sells Commons, replants the patches you pick",
	},
	-- Id kept as "GrowthSpeed2x" (owned passes are saved under it); the effect is `multiplier`
	-- (1.5x since 2026-11-03: the passes together made a player 4x faster than a free one).
	GrowthSpeed2x = {
		id = 2067054408,
		price = 299,
		name = "1.5x Growth Speed",
		description = "Every egg grows 1.5x faster",
		multiplier = 1.5,
	},
	OfflineMutations = {
		id = 2068452355,
		price = 199,
		name = "Offline Mutations",
		description = "Mutation rolls continue while offline",
	},
	PlotSlots10 = { id = 2066616450, price = 349, name = "+10 Plot Slots", description = "Ten permanent extra slots" },
	VIP = {
		id = 2068044354,
		price = 499,
		name = "VIP",
		-- The VIP egg (exclusive species pool) is M5.
		description = "Gold [VIP] chat tag, 1.5x Cash, 50 Gems every day",
		dailyGems = 50,
	},
	-- The Starter Bundle is sold as a developer product (see Products.lua) because it is offered once.
}
