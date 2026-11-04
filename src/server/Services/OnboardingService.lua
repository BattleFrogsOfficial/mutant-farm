--!strict
-- The scripted opening (Config/Onboarding.lua, rules in shared/Onboarding.lua), for profiles
-- created with it (`profile.onboarding.active`): plants a new profile's first egg a few seconds
-- from hatching (GrowthService turns that egg's hatch into the scripted first hatch), and records
-- the first Egg Shop open (`OpenedShop`), which retires the tray's BUY button, counts play time,
-- and gives one free Solar Flare on the player's own plot once it's due
-- (Onboarding.soloWeatherDue: 2:30 of play, 3 eggs growing, no global event near).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Eggs = require(Shared.Config.Eggs)
local Mutants = require(Shared.Config.Mutants)
local Onboarding = require(Shared.Onboarding)
local OnboardingConfig = require(Shared.Config.Onboarding)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local WeatherService = require(script.Parent.WeatherService)
local Net = require(script.Parent.Parent.Util.Net)

local OnboardingService = {}

function OnboardingService.Init() end

-- The server's own check that the tutorial is on its last step (the earlier steps are done):
-- hatched twice and sold, a soil patch bought (or none left to buy), a Swamp egg ever owned.
function OnboardingService.onAlmanacStep(data: Types.Profile): boolean
	local st = data.stats
	if st.harvested < 2 or st.sold < 1 then
		return false
	end
	if st.slotsBought == 0 and DataService.nextSlotCost(data) ~= nil then
		return false
	end
	if (data.eggs.Swamp or 0) > 0 or (data.eggs.SwampGem or 0) > 0 then
		return true
	end
	for _, slot in data.slots do
		if Eggs.baseOf(slot.eggId) == "Swamp" then
			return true
		end
	end
	for id in data.almanac do
		local species = Mutants.species[id]
		if species and species.tier == "Swamp" then
			return true
		end
	end
	return false
end

function OnboardingService.Start()
	DataService.Loaded:Connect(function(player: Player, data: Types.Profile)
		if data.onboarding.active then
			GrowthService.preplant(player, data)
		end
	end)
	-- The tray's BUY button (the tutorial's buy step) goes for good once the shop has been opened.
	Net.on("OpenedShop", function(player: Player, data: Types.Profile)
		if data.onboarding.active and not data.onboarding.shopOpened then
			data.onboarding.shopOpened = true
			DataService.changed(player)
		end
	end)
	-- The tutorial's last step: the Almanac opened (after the earlier steps) ends it for good.
	Net.on("OpenedAlmanac", function(player: Player, data: Types.Profile)
		if not data.tutorialDone and OnboardingService.onAlmanacStep(data) then
			data.tutorialDone = true
			DataService.changed(player)
		end
	end)
	local w = OnboardingConfig.soloWeather
	while true do
		task.wait(1)
		local now = DataService.now()
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			local o = data and data.onboarding
			if data and o and o.active and not o.weather then
				o.playSeconds += 1
				local growing = DataService.eggCounts(data)
				local near = WeatherService.globalNear(now, w.clearSeconds)
				if
					Onboarding.soloWeatherDue(o.weather, o.playSeconds, growing, near)
					-- No toast: the tutorial card says "WEATHER!" (the toast lane is for events).
					and WeatherService.startPlotEvent(player, data, w.event, "")
				then
					o.weather = true
					DataService.changed(player)
				end
			end
		end
	end
end

return OnboardingService
