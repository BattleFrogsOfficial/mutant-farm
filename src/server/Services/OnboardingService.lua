--!strict
-- The scripted opening (Config/Onboarding.lua, rules in shared/Onboarding.lua), for profiles
-- created with it (`profile.onboarding.active`): plants a new profile's first egg a few seconds
-- from hatching (GrowthService turns that egg's hatch into the scripted first hatch), and records
-- the first Egg Shop open (`OpenedShop`), which retires the tray's BUY button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
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
end

return OnboardingService
