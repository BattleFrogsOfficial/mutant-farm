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

-- Gems to finish a growing egg now: `costPer10Minutes` per started 10 minutes left.
function Costs.skip(secondsLeft: number, costPer10Minutes: number): number
	if secondsLeft <= 0 then
		return 0
	end
	return math.ceil(secondsLeft / 600) * costPer10Minutes
end

-- Cash needed to perform rebirth number `rebirths + 1`: firstCost x costGrowth ^ rebirths.
function Costs.rebirth(rebirths: number): number
	return Rebirths.firstCost * Rebirths.costGrowth ^ rebirths
end

return Costs
