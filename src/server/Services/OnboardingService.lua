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
local Onboarding = require(Shared.Onboarding)
local OnboardingConfig = require(Shared.Config.Onboarding)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local WeatherService = require(script.Parent.WeatherService)
local Net = require(script.Parent.Parent.Util.Net)

local OnboardingService = {}

function OnboardingService.Init() end

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
					and WeatherService.startPlotEvent(player, data, w.event, w.toast)
				then
					o.weather = true
					DataService.changed(player)
				end
			end
		end
	end
end

return OnboardingService
