--!strict
-- Daily login streak. The day index is UTC days since epoch, so it's the same on every server.

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Daily = require(Shared.Config.Daily)
local GameConfig = require(Shared.Config.Game)
local Eggs = require(Shared.Config.Eggs)
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

-- Is the player in the group? GetGroupsAsync isn't cached per session (Player:IsInGroup is), so
-- joining mid-session and tapping Claim works. nil when the check failed.
local function inGroup(player: Player): boolean?
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if not ok then
		return nil
	end
	for _, g in groups do
		if g.Id == GameConfig.groupId then
			return true
		end
	end
	return false
end

-- Updates the permanent +10% Cash bonus (data.inGroup). Leaving the group drops it next check.
local function refreshGroup(player: Player, data: Types.Profile): boolean?
	local member = inGroup(player)
	if member == nil or DataService.get(player) ~= data then
		return nil
	end
	if data.inGroup ~= member then
		data.inGroup = member
		DataService.changed(player)
	end
	return member
end

-- Claim: re-checks membership (turns on the Cash bonus) and gives the one-time eggs.
local claiming: { [Player]: boolean } = {}
local function onClaimGroup(player: Player, data: Types.Profile)
	if GameConfig.groupId == 0 then
		Net.notify(player, "The group reward isn't set up yet", "info")
		return
	end
	if claiming[player] then
		return -- the check yields; one at a time per player
	end
	claiming[player] = true
	local member = refreshGroup(player, data)
	claiming[player] = nil
	if member == nil then
		return
	end
	if not member then
		Net.notify(player, "Join our group first, then tap again!", "info")
		return
	end
	if not data.groupRewardClaimed then
		data.groupRewardClaimed = true
		for eggId, count in GameConfig.groupReward.eggs or {} do
			if Eggs.tiers[eggId] then
				data.eggs[eggId] = (data.eggs[eggId] or 0) + count
			end
		end
	end
	Net.notify(player, "👥 Thanks for joining! +10% Cash while you're in the group", "success")
	DataService.changed(player)
end

function DailyService.Init() end

function DailyService.Start()
	Net.on("ClaimDaily", onClaim)
	Net.on("ClaimGroupReward", onClaimGroup)
	if GameConfig.groupId ~= 0 then
		DataService.Loaded:Connect(function(player, data)
			task.spawn(refreshGroup, player, data)
		end)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		claiming[player] = nil
	end)
end

return DailyService
