--!strict
-- Daily login streak. The day index is UTC days since epoch, so it's the same on every server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Daily = require(Shared.Config.Daily)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)

local DailyService = {}

local function today(): number
	return math.floor(DataService.now() / 86400)
end

local function onClaim(player: Player, data: Types.Profile)
	local status = DataService.dailyStatus(data)
	local day = status.day
	if not status.canClaim then
		return
	end
	local reward = Daily.rewards[day]
	if reward.kind == "eggs" then
		data.eggs[reward.egg] = (data.eggs[reward.egg] or 0) + reward.count
	elseif reward.kind == "cash" then
		local amount = math.max(reward.min, math.floor(DataService.incomePerMinute(data) * reward.minutes))
		if not EconomyService.addCash(player, data, amount, "TimedReward", "Daily_" .. day) then
			return
		end
	end
	data.streak.count = (if status.streak > 0 then status.streak else 0) + 1
	data.streak.day = day
	data.streak.lastClaimDay = today()
	Net.notify(player, string.format("Day %d reward: %s!", day, reward.label), "success")
	DataService.changed(player)
end

function DailyService.Init() end

function DailyService.Start()
	Net.on("ClaimDaily", onClaim)
end

return DailyService
