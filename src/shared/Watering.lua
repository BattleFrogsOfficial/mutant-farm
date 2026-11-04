--!strict
-- Watering rules shared by the server (WaterService), the HUD's growth circle and the simulator:
-- the boost offers (rolled by the server), when the next tap is allowed, and where the circle
-- shows up next on the screen. The growth math itself is in Growth.lua (Growth.Water).

local Config = script.Parent.Config
local GameConfig = require(Config.Game)

local Watering = {}

local offers = GameConfig.water.tapOffers
local totalWeight = 0
for _, offer in offers do
	totalWeight += offer[2]
end

-- The offer for a uniform `u` in [0, 1): walks the weights, lower multipliers likelier.
function Watering.offerFor(u: number): number
	local pick = u * totalWeight
	for _, offer in offers do
		pick -= offer[2]
		if pick < 0 then
			return offer[1]
		end
	end
	return offers[#offers][1]
end

-- The chance of each multiplier, for docs and tests: { [multiplier] = 0..1 }.
function Watering.odds(): { [number]: number }
	local out = {}
	for _, offer in offers do
		out[offer[1]] = offer[2] / totalWeight
	end
	return out
end

-- The average offer (the simulator's perfect tapper grows at this while online).
function Watering.averageOffer(): number
	local sum = 0
	for _, offer in offers do
		sum += offer[1] * offer[2]
	end
	return sum / totalWeight
end

-- A tap is allowed once the circle is back (`readyAt`: the boost's end plus the vanish gap; a
-- little early is fine: latency).
function Watering.canTap(now: number, readyAt: number): boolean
	return now >= readyAt - GameConfig.water.tapGrace
end

-- The boost a tap starts at `now`: until when it runs.
function Watering.boostEnd(now: number): number
	return now + GameConfig.water.boostSeconds
end

-- The vanish gap after a boost, from a uniform `u` in [0, 1): gapMin..gapMax seconds.
function Watering.gapFor(u: number): number
	local w = GameConfig.water
	return w.gapMin + u * (w.gapMax - w.gapMin)
end

-- When the circle comes back after a boost that ends at `boostEnd` (gap rolled from `u`).
function Watering.readyAt(boostEnd: number, u: number): number
	return boostEnd + Watering.gapFor(u)
end

-- The circle shows while a boost runs, or once its gap is over (never during the gap).
function Watering.circleShown(now: number, boostUntil: number, readyAt: number): boolean
	return now < boostUntil or now >= readyAt
end

-- One whole tap cycle's average speed for a perfect tapper on the pad: `boostSeconds` at the
-- offer (or the pad, the higher) and the average gap at `base` (the pad's 2x).
function Watering.cycleRate(base: number): number
	local w = GameConfig.water
	local boosted = 0
	for mult, chance in Watering.odds() do
		boosted += math.max(base, mult) * chance
	end
	local gap = (w.gapMin + w.gapMax) / 2
	return (w.boostSeconds * boosted + gap * base) / (w.boostSeconds + gap)
end

-- The next spot for the circle: any of the `count` spots except `last`, from a uniform `u`.
function Watering.nextSpot(last: number?, count: number, u: number): number
	if count <= 1 then
		return 1
	end
	local choices = if last and last >= 1 and last <= count then count - 1 else count
	local i = math.min(choices - 1, math.floor(u * choices)) + 1
	if last and last >= 1 and last <= count and i >= last then
		i += 1
	end
	return i
end

return Watering
