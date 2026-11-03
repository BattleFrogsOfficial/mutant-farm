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

-- A tap is allowed once the last boost has run out (a little early is fine: latency).
function Watering.canTap(now: number, boostUntil: number): boolean
	return now >= boostUntil - GameConfig.water.tapGrace
end

-- The boost a tap starts at `now`: until when it runs.
function Watering.boostEnd(now: number): number
	return now + GameConfig.water.tapSeconds
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
