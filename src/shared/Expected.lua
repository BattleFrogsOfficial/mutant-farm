--!strict
-- Expected values: what an egg is worth on average and how long it takes, before any luck
-- shows up. Used for the farm income sign, the HUD's $/min, and tools/sim.luau.

local Config = script.Parent.Config
local Eggs = require(Config.Eggs)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local Sizes = require(Config.Sizes)
local Rolls = require(script.Parent.Rolls)

local Expected = {}

function Expected.sizeMultiplier(luck: number): number
	local ev = 0
	for i, w in Rolls.sizeWeights(luck) do
		local band = Sizes.bands[i]
		ev += w / 100 * (band.min + band.max) / 2
	end
	return ev
end

function Expected.mutationMultiplier(luck: number, oddsBonus: number): number
	local ev = 1
	for _, id in Mutations.order do
		local p = 1 - (1 - Rolls.mutationChance(id, luck, oddsBonus)) ^ Mutations.rollsPerGrow
		ev *= 1 + p * (Mutations.info[id].multiplier - 1)
	end
	return ev
end

-- Expected sell value (before cash multiplier) and grow seconds (at speed 1) of one egg.
-- Pass `rarity` when it's already known (e.g. a planted egg) to skip the rarity average.
function Expected.egg(tierId: string, luck: number, oddsBonus: number, rarity: string?): (number, number)
	local tier = Eggs.tiers[tierId]
	local value, time = 0, 0
	if rarity then
		value = Rarities.info[rarity].valueMultiplier
		time = Rarities.info[rarity].growMultiplier
	else
		for r, w in Rolls.rarityWeights(tierId, luck) do
			value += w / 100 * Rarities.info[r].valueMultiplier
			time += w / 100 * Rarities.info[r].growMultiplier
		end
	end
	return tier.baseValue * value * Expected.mutationMultiplier(luck, oddsBonus) * Expected.sizeMultiplier(luck),
		tier.growTime * time
end

return Expected
