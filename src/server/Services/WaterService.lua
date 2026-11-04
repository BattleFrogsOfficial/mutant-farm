--!strict
-- Watering, both halves:
--   * the water pad on each plot: the plot grows at Game.water.padMultiplier while its owner
--     stands on it (PlotService watches positions and calls WaterService.setOnPad);
--   * the HUD's growth circle: `TapBoost` grows the plot at the offered multiplier for
--     Game.water.boostSeconds, then the circle vanishes for a gap the server rolls
--     (`waterReadyAt`; taps before it are refused) and the server rolls the next offer (the
--     client never picks one). Only while the owner stands on the pad.
-- Rules in shared/Watering.lua, the growth math in shared/Growth.lua. Every change settles the
-- plot first, so growth up to now uses the old rate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Watering = require(Shared.Watering)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local Net = require(script.Parent.Parent.Util.Net)

local WaterService = {}

local rng = Random.new()

local function rollOffer(): number
	return Watering.offerFor(rng:NextNumber())
end

-- An offer from before a config change that no longer exists is rolled again.
local function ensureOffer(data: Types.Profile)
	if Watering.odds()[data.waterOffer] == nil then
		data.waterOffer = rollOffer()
	end
end

-- The owner stepped onto (true) or off (false) their plot's water pad.
function WaterService.setOnPad(player: Player, on: boolean)
	local data = DataService.get(player)
	if not data or data.onPad == on then
		return
	end
	GrowthService.settleAndAnnounce(player, data)
	data.onPad = on
	if on then
		data.stats.padVisits += 1
	end
	DataService.changed(player)
end

-- The growth circle was tapped: the current offer runs for boostSeconds, the circle's vanish
-- gap is rolled and a new offer too. Ignored while a boost runs or during the gap.
local function onTapBoost(player: Player, data: Types.Profile)
	local now = DataService.now()
	-- The circle belongs to the pad: only while standing on it.
	if not data.onPad or not Watering.canTap(now, math.max(data.wateredUntil, data.waterReadyAt)) then
		return
	end
	ensureOffer(data)
	GrowthService.settleAndAnnounce(player, data)
	data.waterMult = data.waterOffer
	data.wateredUntil = Watering.boostEnd(now)
	data.waterReadyAt = Watering.readyAt(data.wateredUntil, rng:NextNumber())
	data.waterOffer = rollOffer()
	data.stats.waters += 1
	DataService.changed(player)
end

function WaterService.Init() end

function WaterService.Start()
	DataService.Loaded:Connect(function(player, data)
		ensureOffer(data)
		DataService.changed(player)
	end)
	Net.on("TapBoost", onTapBoost)
end

return WaterService
