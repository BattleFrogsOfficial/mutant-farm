--!strict
-- Cash upgrades. Every cost is multiplied by (1 + costBonusPerRebirth x rebirths), the same
-- curve as the rebirth Cash multiplier, so upgrades cost the same share of income after a reset
-- (see shared/Costs.lua). A steeper curve (e.g. 5x per rebirth) makes rebirthing a net loss.

return {
	costBonusPerRebirth = 0.5,

	slots = {
		base = 6,
		max = 40,
		firstCost = 200, -- cost of slot 7
		costGrowth = 1.5, -- each next slot costs 1.5x the last
	},

	growthSpeed = {
		levels = 5,
		bonusPerLevel = 0.10, -- +10% growth speed per level
		firstCost = 2_000,
		costGrowth = 3,
	},

	mutationOdds = {
		levels = 5,
		bonusPerLevel = 0.10, -- +10% mutation chance per level
		firstCost = 2_000,
		costGrowth = 3,
	},
}
