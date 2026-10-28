--!strict
-- Server entry point. Every service exposes Init() (no yielding, no cross-service calls)
-- and Start() (may use other services). Order below is the dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.init()

local Services = script.Parent.Services
local order = {
	require(Services.DataService),
	require(Services.EconomyService),
	require(Services.PlotService),
	require(Services.GrowthService),
	require(Services.DailyService),
}

for _, service in order do
	service.Init()
end
for _, service in order do
	task.spawn(service.Start)
end
