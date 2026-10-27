--!strict
-- The single roll path for rarity, mutations and size. A luck value changes all three.

local Config = script.Parent.Config
local Eggs = require(Config.Eggs)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local Sizes = require(Config.Sizes)
local GameConfig = require(Config.Game)

local Rolls = {}

function Rolls.clampLuck(luck: number): number
	return math.clamp(luck, 1, GameConfig.maxLuck)
end

-- Uncommon-and-above weights are multiplied by luck, then everything renormalizes to 100.
function Rolls.rarityWeights(tierId: string, luck: number): { [string]: number }
	luck = Rolls.clampLuck(luck)
	local odds = Eggs.tiers[tierId].odds
	local raw = {}
	local total = 0
	for _, rarity in Rarities.order do
		local w = odds[rarity] or 0
		if rarity ~= "Common" then
			w *= luck
		end
		raw[rarity] = w
		total += w
	end
	for rarity, w in raw do
		raw[rarity] = w / total * 100
	end
	return raw
end

function Rolls.rollRarity(rng: any, tierId: string, luck: number): string
	return rng:weighted(Rarities.order, Rolls.rarityWeights(tierId, luck))
end

-- Chance that one roll grants `mutationId`. oddsBonus is the Mutation Odds upgrade (0.1 per level).
function Rolls.mutationChance(mutationId: string, luck: number, oddsBonus: number?): number
	local base = Mutations.info[mutationId].chancePerRoll
	return math.min(1, base * Rolls.clampLuck(luck) * (1 + (oddsBonus or 0)))
end

-- One mutation roll. Returns the mutation ids newly gained (usually none).
function Rolls.rollMutations(rng: any, existing: { string }, luck: number, oddsBonus: number?): { string }
	local has = {}
	for _, id in existing do
		has[id] = true
	end
	local gained = {}
	for _, id in Mutations.order do
		if not has[id] and rng:next() < Rolls.mutationChance(id, luck, oddsBonus) then
			table.insert(gained, id)
		end
	end
	return gained
end

function Rolls.sizeWeights(luck: number): { number }
	luck = Rolls.clampLuck(luck)
	local weights = {}
	local total = 0
	for i, band in Sizes.bands do
		local w = band.weight * (if band.luckBoosted then luck else 1)
		weights[i] = w
		total += w
	end
	for i, w in weights do
		weights[i] = w / total * 100
	end
	return weights
end

-- Size multiplier rounded to 2 decimals.
function Rolls.rollSize(rng: any, luck: number): number
	local weights = Rolls.sizeWeights(luck)
	local pick = rng:next() * 100
	local band = Sizes.bands[#Sizes.bands]
	for i, w in weights do
		pick -= w
		if pick < 0 then
			band = Sizes.bands[i]
			break
		end
	end
	local size = band.min + (band.max - band.min) * rng:next()
	return math.floor(size * 100 + 0.5) / 100
end

return Rolls
