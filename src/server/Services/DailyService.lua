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

-- Group reward: join the Roblox group (Game.groupId), claim once.
local function onClaimGroup(player: Player, data: Types.Profile)
	local cfg = GameConfig
	if data.groupRewardClaimed then
		return
	end
	if cfg.groupId == 0 then
		Net.notify(player, "The group reward isn't set up yet", "info")
		return
	end
	-- Claim first (the group check yields; concurrent taps must not all pass), undo if not a member.
	data.groupRewardClaimed = true
	-- GetGroupsAsync isn't cached per session, unlike Player:IsInGroup, so joining mid-session works.
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	local inGroup = false
	if ok then
		for _, g in groups do
			if g.Id == cfg.groupId then
				inGroup = true
			end
		end
	end
	if DataService.get(player) ~= data then
		return -- left while we waited
	end
	if not inGroup then
		data.groupRewardClaimed = false
		Net.notify(player, "Join our group first, then tap again!", "info")
		return
	end
	local reward = cfg.groupReward
	if reward.gems then
		EconomyService.addGems(player, data, reward.gems, "Gameplay", "GroupReward")
	end
	for eggId, count in reward.eggs or {} do
		if Eggs.tiers[eggId] then
			data.eggs[eggId] = (data.eggs[eggId] or 0) + count
		end
	end
	Net.notify(player, "👥 Thanks for joining! Group reward claimed", "success")
	DataService.changed(player)
end

function DailyService.Init() end

function DailyService.Start()
	Net.on("ClaimDaily", onClaim)
	Net.on("ClaimGroupReward", onClaimGroup)
end

return DailyService
