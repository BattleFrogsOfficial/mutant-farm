--!strict
-- Cost curves for slots, upgrades and rebirths.

local Config = script.Parent.Config
local Upgrades = require(Config.Upgrades)
local Rebirths = require(Config.Rebirths)

local Costs = {}

local function rebirthScale(rebirths: number): number
	return 1 + Upgrades.costBonusPerRebirth * rebirths
end

-- Cost to buy slot number `slotNumber` (7..40). nil if out of range.
function Costs.slot(slotNumber: number, rebirths: number): number?
	local cfg = Upgrades.slots
	if slotNumber <= cfg.base or slotNumber > cfg.max then
		return nil
	end
	return math.floor(cfg.firstCost * cfg.costGrowth ^ (slotNumber - cfg.base - 1) * rebirthScale(rebirths))
end

-- Cost to go from `level` to `level + 1` for "growthSpeed" or "mutationOdds". nil if maxed.
function Costs.upgrade(kind: string, level: number, rebirths: number): number?
	local cfg = (Upgrades :: any)[kind]
	if level >= cfg.levels then
		return nil
	end
	return math.floor(cfg.firstCost * cfg.costGrowth ^ level * rebirthScale(rebirths))
end

-- Cash needed to perform rebirth number `rebirths + 1`.
function Costs.rebirth(rebirths: number): number
	local n = rebirths + 1
	local costs = Rebirths.costs
	if n <= #costs then
		return costs[n]
	end
	return costs[#costs] * Rebirths.costGrowthAfterTable ^ (n - #costs)
end

return Costs
