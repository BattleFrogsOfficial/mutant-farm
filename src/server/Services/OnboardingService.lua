--!strict
-- The scripted opening (Config/Onboarding.lua, rules in shared/Onboarding.lua), for profiles
-- created with it (`profile.onboarding.active`): plants a new profile's first egg a few seconds
-- from hatching. GrowthService turns that egg's hatch into the scripted first hatch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)

local OnboardingService = {}

function OnboardingService.Init() end

function OnboardingService.Start()
	DataService.Loaded:Connect(function(player: Player, data: Types.Profile)
		if data.onboarding.active then
			GrowthService.preplant(player, data)
		end
	end)
end

return OnboardingService
