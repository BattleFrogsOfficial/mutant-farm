--!strict
-- Growth is a pure function of timestamps: no per-frame work, offline progress for free,
-- and the client can run the exact same math to draw timers between server updates.
--
-- A slot stores `growth` (effective seconds grown) as of `updatedAt`. Speed is constant
-- between events except for watering, which is a plot-wide window ending at `wateredUntil`.
-- Every plot-wide speed change settles all slots first, so a window always starts after
-- the slot's `updatedAt`.

local Config = script.Parent.Config
local Eggs = require(Config.Eggs)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local GameConfig = require(Config.Game)
local Upgrades = require(Config.Upgrades)

local Growth = {}

function Growth.requiredSeconds(tierId: string, rarity: string): number
	return Eggs.tiers[tierId].growTime * Rarities.info[rarity].growMultiplier
end

-- Multiplier from everything except watering.
function Growth.speed(growthUpgradeLevel: number, hasSpeedPass: boolean): number
	local upgrade = 1 + Upgrades.growthSpeed.bonusPerLevel * growthUpgradeLevel
	return upgrade * (if hasSpeedPass then 2 else 1)
end

-- Growth after advancing from `from` to `to`.
function Growth.advance(growth: number, from: number, to: number, wateredUntil: number, speed: number): number
	if to <= from then
		return growth
	end
	local watered = math.max(0, math.min(to, wateredUntil) - from)
	return growth + speed * ((to - from) + (GameConfig.waterMultiplier - 1) * watered)
end

-- Seconds of real time until `growth` reaches `required`.
function Growth.secondsRemaining(
	growth: number,
	required: number,
	now: number,
	wateredUntil: number,
	speed: number
): number
	local remaining = required - growth
	if remaining <= 0 then
		return 0
	end
	local wateredLeft = math.max(0, wateredUntil - now)
	local wateredRate = speed * GameConfig.waterMultiplier
	if remaining <= wateredRate * wateredLeft then
		return remaining / wateredRate
	end
	return wateredLeft + (remaining - wateredRate * wateredLeft) / speed
end

-- Number of mutation rolls whose growth threshold lies in (oldGrowth, newGrowth].
-- Roll k (1..rollsPerGrow) happens when growth reaches required * k / rollsPerGrow.
function Growth.rollsCrossed(oldGrowth: number, newGrowth: number, required: number): number
	local n = Mutations.rollsPerGrow
	local before = math.clamp(math.floor(oldGrowth / required * n + 1e-9), 0, n)
	local after = math.clamp(math.floor(newGrowth / required * n + 1e-9), 0, n)
	return after - before
end

return Growth
