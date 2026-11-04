--!strict
-- Watering, both halves:
--   * the water pad on each plot: the plot grows at Game.water.padMultiplier while its owner
--     stands on it (PlotService watches positions and calls WaterService.setOnPad);
--   * the HUD's growth circle: `TapBoost` grows the plot at the offered multiplier for
--     Game.water.tapSeconds, then the server rolls the next offer (the client never picks one).
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

-- The growth circle was tapped: the current offer runs for tapSeconds, and a new one is rolled.
-- Ignored while the last boost is still running (the circle is on its cooldown).
local function onTapBoost(player: Player, data: Types.Profile)
	local now = DataService.now()
	-- The boost belongs to the pad: only while standing on it.
	if not data.onPad or not Watering.canTap(now, data.wateredUntil) then
		return
	end
	ensureOffer(data)
	GrowthService.settleAndAnnounce(player, data)
	data.waterMult = data.waterOffer
	data.wateredUntil = Watering.boostEnd(now)
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
