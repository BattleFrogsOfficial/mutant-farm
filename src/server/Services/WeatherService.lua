--!strict
-- Server-wide weather events from Config/Weather.lua. Every 20-30 minutes one event (weighted;
-- Glitch Storm is 1 in 6) runs for 120 s; while it runs, every online player's growing eggs roll
-- for the event's mutation every rollEverySeconds (a chance per tick, not a forced mutation).
-- The schedule is replicated as Workspace attributes so every client can show the countdown
-- ("☢ Acid Rain in 4:12", a chip from 5 min before) and draw the weather.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Weather = require(Shared.Config.Weather)
local WeatherRules = require(Shared.WeatherRules)
local Rng = require(Shared.Rng)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)

local WeatherService = {}

local random = Random.new()
local rng = Rng.new(random:NextInteger(1, 2 ^ 31 - 1))

local function schedule(at: number)
	workspace:SetAttribute("WeatherNextId", WeatherRules.pick(rng))
	workspace:SetAttribute("WeatherNextAt", at)
end

local function waitUntil(at: number)
	while DataService.now() < at do
		task.wait(math.max(at - DataService.now(), 0.05))
	end
end

-- One event: a roll on every online player's growing eggs when it starts and every
-- rollEverySeconds after (WeatherRules.rolls: 4 for 120 s), then clear it.
local function run(eventId: string)
	local event = (Weather.events :: any)[eventId]
	local startAt = DataService.now()
	local endsAt = startAt + event.durationSeconds
	workspace:SetAttribute("WeatherId", eventId)
	workspace:SetAttribute("WeatherEndsAt", endsAt)
	schedule(endsAt + random:NextNumber(Weather.minIntervalSeconds, Weather.maxIntervalSeconds))
	for k = 0, WeatherRules.rolls(eventId) - 1 do
		waitUntil(startAt + k * Weather.rollEverySeconds)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data and next(data.slots) then
				GrowthService.weatherRoll(player, data, eventId)
			end
		end
	end
	waitUntil(endsAt)
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
