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

	-- Gem upgrades (shared/GemUpgrades.lua): bought with Gems, kept through every rebirth, not
	-- random and not policy-gated. Sink "GemUpgrade_<kind>".
	gem = {
		-- +4 mutants standing in the pen (and pinnable), once per rebirth level (level <= rebirths + 1).
		penSlots = { slotsPerLevel = 4, cost = 150 },
		-- +10% luck per level, added to the Almanac's permanent luck, under Game.maxLuck.
		luck = { bonusPerLevel = 0.10, costs = { 200, 400, 800 } },
		-- +2 h of offline mutation rolls per level (on top of Game.offlineMutationCap); MAX while
		-- the Offline Mutations pass is owned (it already rolls the whole time away).
		offline = { secondsPerLevel = 2 * 60 * 60, costs = { 100, 200, 400 } },
	},
}
