--!strict
-- Group Reward (Game.groupId, 0 = off). Members get +groupCashBonus Cash for as long as they're in
-- the group (data.inGroup, part of the cash multiplier) and the one-time groupReward eggs.
--   * Join: checked with Player:IsInGroup (leaving the group drops the bonus next join).
--   * First sell: the offer is shown once ("GroupOffer"); the client's Join button opens Roblox's
--     join prompt and then sends ClaimGroupReward.
--   * Mid-session: IsInGroup is cached per server, so ClaimGroupReward and sales re-check with
--     GetGroupsAsync (throttled), and a player who joins mid-session gets the bonus on their next
--     sell.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Eggs = require(Shared.Config.Eggs)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Parent.Util.Net)

local GroupRewardService = {}

-- Seconds between the uncached membership checks a player's sales can trigger.
local RECHECK_SECONDS = 30

local lastCheck: { [Player]: number } = {}
local checking: { [Player]: boolean } = {}

-- Uncached membership check (GetGroupsAsync). nil when the check failed.
local function isMember(player: Player): boolean?
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

-- Sets data.inGroup from a membership result. Returns the result (nil = unknown, no change).
local function apply(player: Player, data: Types.Profile, member: boolean?): boolean?
	if member == nil or DataService.get(player) ~= data then
		return nil
	end
	if data.inGroup ~= member then
		data.inGroup = member
		DataService.changed(player)
	end
	return member
end

-- Before a sale: if a non-member may have joined mid-session, re-check (yields, throttled), so the
-- sale already pays the bonus.
function GroupRewardService.beforeSale(player: Player, data: Types.Profile)
	if GameConfig.groupId == 0 or data.inGroup or checking[player] then
		return
	end
	local now = DataService.now()
	if now - (lastCheck[player] or -math.huge) < RECHECK_SECONDS then
		return
	end
	lastCheck[player] = now
	checking[player] = true
	apply(player, data, isMember(player))
	checking[player] = nil
end

-- After a player's first sale: show the offer once (never to members).
function GroupRewardService.afterSale(player: Player, data: Types.Profile)
	if GameConfig.groupId == 0 or data.groupOffered or data.inGroup then
		return
	end
	data.groupOffered = true
	Net.fire(player, "GroupOffer")
	DataService.changed(player)
end

-- Claim (after joining from the offer or the Daily panel): re-check membership, turn on the Cash
-- bonus and give the one-time eggs.
local function onClaim(player: Player, data: Types.Profile)
	if GameConfig.groupId == 0 then
		Net.notify(player, "The group reward isn't set up yet", "info")
		return
	end
	if checking[player] then
		return -- the check yields; one at a time per player
	end
	checking[player] = true
	lastCheck[player] = DataService.now()
	local member = apply(player, data, isMember(player))
	checking[player] = nil
	if member == nil then
		return
	end
	if not member then
		Net.notify(player, "Join our group first, then tap again!", "info")
		return
	end
	local eggs = ""
	if not data.groupRewardClaimed then
		data.groupRewardClaimed = true
		for eggId, count in GameConfig.groupReward.eggs or {} do
			if Eggs.tiers[eggId] then
				data.eggs[eggId] = (data.eggs[eggId] or 0) + count
				eggs ..= string.format(" +%d %s", count, Eggs.tiers[eggId].name)
			end
		end
	end
	Net.notify(
		player,
		string.format("👥 Thanks for joining! +%d%% Cash forever", math.floor(GameConfig.groupCashBonus * 100 + 0.5))
			.. eggs,
		"success"
	)
	DataService.changed(player)
end

function GroupRewardService.Init() end

function GroupRewardService.Start()
	Net.on("ClaimGroupReward", onClaim)
	DataService.Loaded:Connect(function(player, data)
		if GameConfig.groupId == 0 then
			return
		end
		-- On join: Player:IsInGroup (the first call in this server is fresh).
		local ok, member = pcall(player.IsInGroup, player, GameConfig.groupId)
		apply(player, data, if ok then member else nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCheck[player] = nil
		checking[player] = nil
	end)
end

return GroupRewardService
