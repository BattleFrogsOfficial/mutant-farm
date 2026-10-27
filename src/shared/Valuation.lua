--!strict
-- What a mutant is worth. Order: tier base value x rarity x mutations x size x cash multiplier.

local Config = script.Parent.Config
local Eggs = require(Config.Eggs)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local Rebirths = require(Config.Rebirths)

local Valuation = {}

export type Mutant = {
	tier: string,
	rarity: string,
	mutations: { string },
	size: number,
}

function Valuation.mutationMultiplier(mutations: { string }): number
	local m = 1
	for _, id in mutations do
		m *= Mutations.info[id].multiplier
	end
	return m
end

-- Tier x rarity only. Pen income is computed from this so mutations can't inflate income.
function Valuation.baseValue(mutant: Mutant): number
	return Eggs.tiers[mutant.tier].baseValue * Rarities.info[mutant.rarity].valueMultiplier
end

function Valuation.cashMultiplier(rebirths: number, hasVip: boolean): number
	return (1 + Rebirths.cashBonusPerRebirth * rebirths) * (if hasVip then 1.5 else 1)
end

function Valuation.sellValue(mutant: Mutant, cashMultiplier: number): number
	return math.floor(
		Valuation.baseValue(mutant) * Valuation.mutationMultiplier(mutant.mutations) * mutant.size * cashMultiplier
	)
end

-- Upper bound on a single sale for a player at this rebirth count. Used as a server sanity check.
function Valuation.maxSingleSale(rebirths: number, cashMultiplier: number): number
	local best = 0
	for _, tier in Eggs.tiers do
		if tier.unlockRebirth <= rebirths then
			best = math.max(best, tier.baseValue)
		end
	end
	local maxMutation = 1
	for _, info in Mutations.info do
		maxMutation *= info.multiplier
	end
	return best * Rarities.info.Legendary.valueMultiplier * maxMutation * 3 * cashMultiplier
end

return Valuation
