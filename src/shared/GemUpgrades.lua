--!strict
-- Gem upgrades (Config/Upgrades.gem): Pen Slots, Permanent Luck, Offline Mutations. Bought with
-- Gems through the BuyGemUpgrade intent, kept through rebirth. Pure: the server's handler and the
-- Upgrades panel share these rules.

local Config = script.Parent.Config
local Upgrades = require(Config.Upgrades)
local GameConfig = require(Config.Game)

local GemUpgrades = {}

GemUpgrades.order = { "penSlots", "luck", "offline" }

-- The level of `kind` in a profile's gemUpgrades table (missing = 0).
function GemUpgrades.level(levels: { [string]: number }?, kind: string): number
	return if levels then levels[kind] or 0 else 0
end

-- How many levels `kind` has (Pen Slots: one per rebirth level reached so far).
function GemUpgrades.levels(kind: string, rebirths: number): number
	if kind == "penSlots" then
		return rebirths + 1
	end
	return #(Upgrades.gem :: any)[kind].costs
end

-- Gems for the next level of `kind`, or nil when it can't be bought now: maxed, Pen Slots already
-- bought at this rebirth level, or Offline Mutations while the pass is owned.
function GemUpgrades.cost(kind: string, level: number, rebirths: number, ownsOfflinePass: boolean): number?
	local cfg = (Upgrades.gem :: any)[kind]
	if not cfg then
		return nil
	end
	if kind == "offline" and ownsOfflinePass then
		return nil
	end
	if level >= GemUpgrades.levels(kind, rebirths) then
		return nil
	end
	return if kind == "penSlots" then cfg.cost else cfg.costs[level + 1]
end

-- Mutants the pen shows (and the pin cap): Game.penDisplayCount + 4 per Pen Slots level.
function GemUpgrades.penCapacity(penSlotsLevel: number): number
	return GameConfig.penDisplayCount + Upgrades.gem.penSlots.slotsPerLevel * penSlotsLevel
end

-- Permanent luck from the upgrade: +0.1 per level (added to the Almanac's).
function GemUpgrades.luckBonus(luckLevel: number): number
	return Upgrades.gem.luck.bonusPerLevel * luckLevel
end

-- Seconds after leaving that offline mutation rolls still run: Game.offlineMutationCap + 2 h per
-- Offline Mutations level.
function GemUpgrades.offlineCap(offlineLevel: number): number
	return GameConfig.offlineMutationCap + Upgrades.gem.offline.secondsPerLevel * offlineLevel
end

return GemUpgrades
