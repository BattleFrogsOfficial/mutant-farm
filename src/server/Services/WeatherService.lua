--!strict
-- Server-wide weather events from Config/Weather.lua. Every 20-30 minutes one event (weighted)
-- runs for its duration; while it runs, every online player's growing eggs roll for the event's
-- mutation every rollEverySeconds. The schedule is replicated as Workspace attributes so every
-- client can show "☢ Acid Rain in 4:12" and draw the weather.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Weather = require(Shared.Config.Weather)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)

local WeatherService = {}

local random = Random.new()

local function pick(): string
	local total = 0
	for _, e in Weather.events do
		total += e.weight
	end
	local r = random:NextNumber() * total
	for id, e in Weather.events do
		r -= e.weight
		if r <= 0 then
			return id
		end
	end
	return next(Weather.events) :: string
end

local function schedule(at: number)
	workspace:SetAttribute("WeatherNextId", pick())
	workspace:SetAttribute("WeatherNextAt", at)
end

local function run(eventId: string)
	local event = (Weather.events :: any)[eventId]
	local now = DataService.now()
	workspace:SetAttribute("WeatherId", eventId)
	workspace:SetAttribute("WeatherEndsAt", now + event.durationSeconds)
	schedule(now + event.durationSeconds + random:NextNumber(Weather.minIntervalSeconds, Weather.maxIntervalSeconds))
	local endsAt = now + event.durationSeconds
	while DataService.now() < endsAt do
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data and next(data.slots) then
				GrowthService.weatherRoll(player, data, event.mutation, event.chancePerRoll or Weather.chancePerRoll)
			end
		end
		task.wait(math.min(Weather.rollEverySeconds, math.max(endsAt - DataService.now(), 0.1)))
	end
	workspace:SetAttribute("WeatherId", "")
	workspace:SetAttribute("WeatherEndsAt", 0)
end

function WeatherService.Init()
	workspace:SetAttribute("WeatherId", "")
	workspace:SetAttribute("WeatherEndsAt", 0)
end

function WeatherService.Start()
	schedule(DataService.now() + Weather.firstEventSeconds)
	while true do
		task.wait(1)
		if DataService.now() >= (workspace:GetAttribute("WeatherNextAt") :: number) then
			run(workspace:GetAttribute("WeatherNextId") :: string)
		end
	end
end

return WeatherService
