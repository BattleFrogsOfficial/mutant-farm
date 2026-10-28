--!strict
-- Client entry point. Controllers render and send intents; they never decide outcomes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.init()

local Controllers = script.Parent.Controllers
local order = {
	require(Controllers.StateController),
	require(Controllers.PlotController),
	require(Controllers.HatchController),
	require(Controllers.TutorialController),
	require(Controllers.WeatherController),
	require(Controllers.ZoneController),
	require(Controllers.UIController),
}

for _, controller in order do
	controller.Init()
end
for _, controller in order do
	task.spawn(controller.Start)
end
