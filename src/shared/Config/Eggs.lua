--!strict
-- Egg tiers. All balance numbers for eggs live here; logic never hardcodes them.
-- growTime is in seconds for a Common hatch; Rarities.growMultiplier stretches it.
-- odds are percentages (must sum to 100) and are what the in-game odds panel shows.

local Eggs = {}

Eggs.order = { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" }

Eggs.tiers = {
	Starter = {
		id = "Starter",
		name = "Starter Egg",
		unlockRebirth = 0,
		cost = 50,
		growTime = 60,
		baseValue = 80,
		color = "#C9F27A",
		odds = { Common = 80, Uncommon = 15, Rare = 4.45, Epic = 0.5, Legendary = 0.05 },
	},
	Swamp = {
		id = "Swamp",
		name = "Swamp Egg",
		unlockRebirth = 0,
		cost = 500,
		growTime = 5 * 60,
		baseValue = 900,
		color = "#5E9C4A",
		odds = { Common = 75, Uncommon = 18, Rare = 6, Epic = 0.93, Legendary = 0.07 },
	},
	Lab = {
		id = "Lab",
		name = "Lab Egg",
		unlockRebirth = 1,
		cost = 5_000,
		growTime = 20 * 60,
		baseValue = 11_000,
		color = "#E8EEF5",
		odds = { Common = 70, Uncommon = 20, Rare = 8, Epic = 1.9, Legendary = 0.1 },
	},
	Toxic = {
		id = "Toxic",
		name = "Toxic Egg",
		unlockRebirth = 2,
		cost = 50_000,
		growTime = 60 * 60,
		baseValue = 130_000,
		color = "#7CFF4A",
		odds = { Common = 65, Uncommon = 22, Rare = 10, Epic = 2.875, Legendary = 0.125 },
	},
	Void = {
		id = "Void",
		name = "Void Egg",
		unlockRebirth = 4,
		cost = 500_000,
		growTime = 3 * 60 * 60,
		baseValue = 1_600_000,
		color = "#2B2140",
		odds = { Common = 60, Uncommon = 24, Rare = 12, Epic = 3.8, Legendary = 0.2 },
	},
	Cosmic = {
		id = "Cosmic",
		name = "Cosmic Egg",
		unlockRebirth = 7,
		cost = 5_000_000,
		growTime = 8 * 60 * 60,
		baseValue = 20_000_000,
		color = "#9B5CFF",
		odds = { Common = 55, Uncommon = 25, Rare = 14, Epic = 5.67, Legendary = 0.33 },
	},
}

return Eggs
