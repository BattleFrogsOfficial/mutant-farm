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

-- +0.5x per rebirth: 1, 1.5, 2, ...
function Valuation.rebirthMultiplier(rebirths: number): number
	return 1 + Rebirths.cashBonusPerRebirth * rebirths
end

-- groupBonus: the group member bonus (e.g. 0.1), 0 for non-members.
function Valuation.cashMultiplier(rebirths: number, hasVip: boolean, groupBonus: number?): number
	return Valuation.rebirthMultiplier(rebirths) * (if hasVip then 1.5 else 1) * (1 + (groupBonus or 0))
end

function Valuation.sellValue(mutant: Mutant, cashMultiplier: number): number
	return math.floor(
		Valuation.baseValue(mutant) * Valuation.mutationMultiplier(mutant.mutations) * mutant.size * cashMultiplier
	)
end

-- Cash per minute from one mutant standing in the pen: base value (tier x rarity) x rate x the
-- rebirth multiplier. Size, mutations, VIP and the group bonus don't count.
function Valuation.penIncome(mutant: Mutant, rebirthMultiplier: number, ratePerMinute: number): number
	return Valuation.baseValue(mutant) * ratePerMinute * rebirthMultiplier
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
