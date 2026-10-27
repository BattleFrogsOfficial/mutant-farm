--!strict
-- Game passes (one-time). Replace id = 0 with the real IDs from Creator Hub.
-- Wired up in M3.

return {
	Luck2x = { id = 0, price = 399, name = "2x Luck", description = "Doubles rarity and mutation odds" },
	AutoHarvest = {
		id = 0,
		price = 249,
		name = "Auto-Harvest",
		description = "Harvests mature mutants and replants the same egg",
	},
	GrowthSpeed2x = { id = 0, price = 299, name = "2x Growth Speed", description = "Halves all grow timers" },
	OfflineMutations = {
		id = 0,
		price = 199,
		name = "Offline Mutations",
		description = "Mutation rolls continue while offline",
	},
	PlotSlots10 = { id = 0, price = 349, name = "+10 Plot Slots", description = "Ten permanent extra slots" },
	VIP = { id = 0, price = 499, name = "VIP", description = "Chat tag, 1.5x Cash, VIP egg, daily 50 Gems" },
	-- The Starter Bundle is sold as a developer product (see Products.lua) because it is offered once.
}
