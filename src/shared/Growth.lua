--!strict
-- Growth is a pure function of timestamps: no per-frame work, offline progress for free,
-- and the client can run the exact same math to draw timers between server updates.
--
-- A slot stores `growth` (effective seconds grown, i.e. seconds at 1x) as of `updatedAt`; timers
-- show required - growth, the time left at 1x, counting down at the current speed, so they never
-- jump when the speed changes. Speed is constant between events except for watering (`Water`):
-- standing on your plot's water pad grows at `padMultiplier` for as long as you stand there, and
-- a tapped boost (only on the pad) grows at its multiplier until `boostUntil`, then back to 2x. Every
-- plot-wide speed change (stepping on or off the pad, a tap) settles all slots first, so a window
-- always starts after the slot's `updatedAt`.

local Config = script.Parent.Config
local Eggs = require(Config.Eggs)
local Rarities = require(Config.Rarities)
local Mutations = require(Config.Mutations)
local GameConfig = require(Config.Game)
local Upgrades = require(Config.Upgrades)
local Passes = require(Config.Passes)

local Growth = {}

-- The plot's watering state: the tap boost (multiplier, until when) and whether the owner is
-- standing on the water pad. Offline nothing is watered (the pad is off and the boost ended).
export type Water = { boostUntil: number, boostMult: number, onPad: boolean }

Growth.DRY = table.freeze({ boostUntil = 0, boostMult = 1, onPad = false }) :: Water

function Growth.water(boostUntil: number?, boostMult: number?, onPad: boolean?): Water
	return { boostUntil = boostUntil or 0, boostMult = boostMult or 1, onPad = onPad == true }
end

-- Watering multipliers: `low` outside the boost window (the pad's, or 1), `high` inside it. The
-- growth circle's boost belongs to the pad: it counts only while you stand on it (off the pad,
-- 1x either way), and when it runs out the pad's 2x is back.
local function rates(water: Water): (number, number)
	if not water.onPad then
		return 1, 1
	end
	local low = GameConfig.water.padMultiplier
	return low, math.max(low, water.boostMult)
end

-- The total speed shown on a timer's chip: the pass and upgrades x the watering at `t` ("2x",
-- "3x" with the 1.5x pass, "7x" boosted).
function Growth.totalSpeed(water: Water, t: number, speed: number): number
	return speed * Growth.waterRate(water, t)
end

-- The watering multiplier at time `t` (1 when dry).
function Growth.waterRate(water: Water, t: number): number
	local low, high = rates(water)
	return if t < water.boostUntil then high else low
end

function Growth.requiredSeconds(tierId: string, rarity: string): number
	return Eggs.tiers[tierId].growTime * Rarities.info[rarity].growMultiplier
end

-- A planted slot's grow time: its tier's, stretched by its rarity (no grow ramp since 2026-11-05).
function Growth.slotRequired(slot: { eggId: string, rarity: string }): number
	return Growth.requiredSeconds(slot.eggId, slot.rarity)
end

-- Multiplier from everything except watering (the pass and the Growth Speed upgrade).
function Growth.speed(growthUpgradeLevel: number, hasSpeedPass: boolean): number
	local upgrade = 1 + Upgrades.growthSpeed.bonusPerLevel * growthUpgradeLevel
	return upgrade * (if hasSpeedPass then Passes.GrowthSpeed2x.multiplier else 1)
end

-- Growth after advancing from `from` to `to` (the pad state held over the whole span: it
-- settles on every change).
-- The timer's text: seconds left AT 1x (the server's progress, never the speed), so a speed change
-- never makes it jump; it counts down at the current total speed.
function Growth.displayRemaining(growth: number, required: number): number
	return math.max(0, required - growth)
end

function Growth.advance(growth: number, from: number, to: number, water: Water, speed: number): number
	if to <= from then
		return growth
	end
	local low, high = rates(water)
	local boosted = math.max(0, math.min(to, water.boostUntil) - from)
	return growth + speed * (low * (to - from) + (high - low) * boosted)
end

-- Seconds of real time until `growth` reaches `required`, if the pad state stays as it is.
function Growth.secondsRemaining(growth: number, required: number, now: number, water: Water, speed: number): number
	local remaining = required - growth
	if remaining <= 0 then
		return 0
	end
	local low, high = rates(water)
	local boostLeft = math.max(0, water.boostUntil - now)
	local boostRate = speed * high
	if remaining <= boostRate * boostLeft then
		return remaining / boostRate
	end
	return boostLeft + (remaining - boostRate * boostLeft) / (speed * low)
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
