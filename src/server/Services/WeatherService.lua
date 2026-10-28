--!strict
-- Weather. Two kinds of events, same roll mechanics (a roll on every growing egg when it starts and
-- every Weather.rollEverySeconds after, at chancePerRoll x luck: WeatherRules / GrowthService):
--
-- * Global: the schedule is a pure function of wall-clock time (shared/Weather.lua scheduleAt), so
--   every server runs the same event at the same moment. Replicated as Workspace attributes
--   (WeatherNextId/NextAt, WeatherId/EndsAt) for the HUD chip and the weather visuals. Announced to
--   everyone in the server: a toast at T-5:00 and T-1:00 and at the start, and a chat line at
--   T-5:00 (`WeatherAnnounce` remote). Glitch Storm is also posted to Discord at T-5:00 by exactly
--   one server: a MemoryStore claim on the event's start time, then a POST to the relay
--   (tools/relay, Config/Game relayUrl, secret WEATHER_RELAY_KEY). Missing pieces skip silently.
-- * Instant Weather (BuyInstantWeather, Products.gems.InstantWeather Gems): a 120 s event on the
--   buyer's plot only. Never two at once for a player; independent of global events. Policy-gated
--   like the Luck Potion. Replicated as the player's PlotWeatherId / PlotWeatherEndsAt attributes
--   (clients draw rain over that island and a small cloud).

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config.Weather)
local GameConfig = require(Shared.Config.Game)
local Products = require(Shared.Config.Products)
local Weather = require(Shared.Weather)
local WeatherRules = require(Shared.WeatherRules)
local ShopRules = require(Shared.ShopRules)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GrowthService = require(script.Parent.GrowthService)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)

local WeatherService = {}

-- This server's id for the announce claim (JobId is "" in Studio).
local serverId = ""

---------------------------------------------------------------------------- rolls

-- Rolls owed by an event `startsAt` at time `now` that haven't happened yet: calls roll() for each.
local function rollsDue(startsAt: number, done: number, now: number, eventId: string, roll: () -> ()): number
	local due = math.min(math.floor((now - startsAt) / Config.rollEverySeconds), WeatherRules.rolls(eventId) - 1)
	for _ = done + 1, due do
		roll()
	end
	return math.max(done, due)
end

local function rollEveryone(eventId: string)
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data and next(data.slots) then
			GrowthService.weatherRoll(player, data, eventId)
		end
	end
end

---------------------------------------------------------------------------- announcements

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function announce(text: string, chat: boolean)
	Remotes.get("WeatherAnnounce"):FireAllClients(text, chat)
end

-- Discord relay ------------------------------------------------------------

local relayWarned = false
local function relayOff(reason: string)
	if not relayWarned then
		relayWarned = true
		warn("[Weather] Discord relay skipped: " .. reason)
	end
end

-- One server per event: claim its start time in a MemoryStore sorted map (expires in an hour).
-- True only for the server whose claim landed.
function WeatherService.claimAnnounce(startsAt: number): boolean
	local ok, result = pcall(function()
		local map = MemoryStoreService:GetSortedMap("WeatherAnnounce")
		return map:UpdateAsync(tostring(startsAt), function(old)
			if old ~= nil then
				return nil -- someone already has it: leave it, store nothing
			end
			return serverId
		end, 3600)
	end)
	if not ok then
		relayOff("MemoryStore unavailable (" .. tostring(result) .. ")")
		return false
	end
	return result == serverId
end

local function postToDiscord(event: Weather.Event)
	if GameConfig.relayUrl == "" then
		relayOff("Game.relayUrl is empty")
		return
	end
	local ok, secret = pcall(HttpService.GetSecret, HttpService, "WEATHER_RELAY_KEY")
	if not ok or secret == nil then
		relayOff("no WEATHER_RELAY_KEY secret")
		return
	end
	if not WeatherService.claimAnnounce(event.startsAt) then
		return
	end
	-- Roblox secrets can only go into headers or the URL, so the key rides in X-Relay-Key; the
	-- Worker accepts it there or as the JSON `key`.
	local sent, err = pcall(HttpService.RequestAsync, HttpService, {
		Url = GameConfig.relayUrl,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json", ["X-Relay-Key"] = secret },
		Body = HttpService:JSONEncode({ event = event.id, startsAt = event.startsAt, link = GameConfig.gameLink }),
	})
	if not sent then
		relayOff("HTTP request failed (" .. tostring(err) .. ")")
	end
end

---------------------------------------------------------------------------- global schedule

local lastNow: number? = nil
local announced: { [number]: { [string]: boolean } } = {} -- startsAt -> what was said
local globalRolls: { [number]: number } = {} -- startsAt -> last roll index done

local function tickGlobal(now: number)
	local current = Weather.scheduleAt(now)
	local upcoming = Weather.nextAfter(now)
	workspace:SetAttribute("WeatherId", if current.active then current.id else "")
	workspace:SetAttribute("WeatherEndsAt", if current.active then current.endsAt else 0)
	workspace:SetAttribute("WeatherNextId", upcoming.id)
	workspace:SetAttribute("WeatherNextAt", upcoming.startsAt)

	local event = (Config.events :: any)[current.id]
	local said = announced[current.startsAt] or {}
	announced[current.startsAt] = said
	-- A threshold counts when this tick crosses it (not at server start, mid-countdown).
	local function crossed(secondsBefore: number): boolean
		local at = current.startsAt - secondsBefore
		return lastNow ~= nil and (lastNow :: number) < at and now >= at
	end
	if not current.active then
		if not said.soon and crossed(Config.announceSeconds) then
			said.soon = true
			announce(string.format(event.soon, event.icon, clock(current.startsAt - now)), true)
			if event.discordAlert then
				task.spawn(postToDiscord, current)
			end
		end
		if not said.warn and crossed(Config.warnSeconds) then
			said.warn = true
			announce(string.format(event.soon, event.icon, clock(current.startsAt - now)), false)
		end
	else
		if not said.start then
			said.start = true
			if lastNow ~= nil and (lastNow :: number) < current.startsAt then
				announce(string.format(event.start, event.icon), false)
			end
			-- Joined mid-event (server start): only the roll for the current tick, not the past ones.
			globalRolls[current.startsAt] = math.floor((now - current.startsAt) / Config.rollEverySeconds) - 1
		end
		globalRolls[current.startsAt] = rollsDue(
			current.startsAt,
			globalRolls[current.startsAt],
			now,
			current.id,
			function()
				rollEveryone(current.id)
			end
		)
	end
	-- Forget old events.
	for startsAt in announced do
		if startsAt < now - 2 * Config.bucketSeconds then
			announced[startsAt] = nil
			globalRolls[startsAt] = nil
		end
	end
	lastNow = now
end

---------------------------------------------------------------------------- Instant Weather

type PlotEvent = { id: string, startsAt: number, endsAt: number, done: number }
local plotEvents: { [Player]: PlotEvent } = {}

local function endPlotEvent(player: Player)
	plotEvents[player] = nil
	player:SetAttribute("PlotWeatherId", nil)
	player:SetAttribute("PlotWeatherEndsAt", nil)
end

function WeatherService.plotEvent(player: Player): PlotEvent?
	return plotEvents[player]
end

local function onBuyInstantWeather(player: Player, data: Types.Profile, eventId: any)
	if not Validate.string(eventId, 32) or not (Config.events :: any)[eventId] then
		return
	end
	if not ShopRules.canBuyInstantWeather(DataService.paidRandomRestricted[player] ~= false) then
		Net.notify(player, "Instant Weather isn't available in your region", "info")
		return
	end
	if plotEvents[player] then
		return -- never stacks with itself (the button is disabled while one runs)
	end
	local cost = Products.gems.InstantWeather.cost
	if not EconomyService.spendGems(player, data, cost, "Shop", "InstantWeather_" .. eventId) then
		Net.notify(player, string.format("Need %d Gems for Instant Weather", cost), "info")
		return
	end
	local event = (Config.events :: any)[eventId]
	local now = DataService.now()
	plotEvents[player] = { id = eventId, startsAt = now, endsAt = now + event.durationSeconds, done = -1 }
	player:SetAttribute("PlotWeatherId", eventId)
	player:SetAttribute("PlotWeatherEndsAt", now + event.durationSeconds)
	Net.notify(
		player,
		string.format("%s %s on your farm for %d s!", event.icon, event.name, event.durationSeconds),
		"success"
	)
	-- The first roll right away.
	plotEvents[player].done = rollsDue(now, -1, now, eventId, function()
		GrowthService.weatherRoll(player, data, eventId)
	end)
end

local function tickPlots(now: number)
	for player, e in plotEvents do
		local data = DataService.get(player)
		if data then
			e.done = rollsDue(e.startsAt, e.done, now, e.id, function()
				GrowthService.weatherRoll(player, data, e.id)
			end)
		end
		if now >= e.endsAt then
			endPlotEvent(player)
		end
	end
end

----------------------------------------------------------------------------

function WeatherService.Init()
	workspace:SetAttribute("WeatherId", "")
	workspace:SetAttribute("WeatherEndsAt", 0)
	serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
end

function WeatherService.Start()
	Net.on("BuyInstantWeather", onBuyInstantWeather)
	Players.PlayerRemoving:Connect(function(player)
		plotEvents[player] = nil
	end)
	while true do
		local now = DataService.now()
		tickGlobal(now)
		tickPlots(now)
		task.wait(1)
	end
end

return WeatherService
