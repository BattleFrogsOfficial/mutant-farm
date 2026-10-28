--!strict
-- The group offer, shown once after the player's first sale (server: GroupRewardService):
-- "Join the group for +10% Cash forever (+2 Swamp Eggs now)". JOIN opens Roblox's join prompt;
-- once they're in, ClaimGroupReward turns the bonus on and gives the eggs. Free, so navy, not pink.

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Eggs = require(Shared.Config.Eggs)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Computed = Fusion.Computed

-- "Join the group for +10% Cash forever (+2 Swamp Eggs now)"
local function offerText(): string
	local eggs = {}
	for eggId, count in GameConfig.groupReward.eggs or {} do
		local tier = Eggs.tiers[eggId]
		table.insert(eggs, string.format("+%d %s%s", count, tier and tier.name or eggId, if count > 1 then "s" else ""))
	end
	return string.format(
		"Join the group for +%d%% Cash forever%s",
		math.floor(GameConfig.groupCashBonus * 100 + 0.5),
		if #eggs > 0 then " (" .. table.concat(eggs, ", ") .. " now)" else ""
	)
end

local joining = false
local function join()
	if joining then
		return
	end
	joining = true
	task.spawn(function()
		local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, GameConfig.groupId)
		joining = false
		if
			ok
			and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember)
		then
			Remotes.get("ClaimGroupReward"):FireServer()
			State.panel:set("none")
		elseif not ok then
			State.toast("Join our group on Roblox, then tap CLAIM in Daily Rewards", "info")
		end
	end)
end

return function()
	return C.panel({
		Title = "👥 Join the group!",
		Accent = Theme.colors.toxicDark,
		Size = UDim2.fromOffset(560, 270),
		IsOpen = Computed(function()
			return State.panel:get() == "groupOffer"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.label({
				Text = offerText(),
				Size = UDim2.new(1, 0, 0, 64),
				TextWrapped = true,
				MaxTextSize = 24,
				TextColor3 = Theme.colors.cream,
				ZIndex = 2,
			}),
			C.label({
				Text = "Members keep the bonus as long as they stay in the group.",
				Position = UDim2.fromOffset(0, 70),
				Size = UDim2.new(1, 0, 0, 22),
				MaxTextSize = 15,
				TextColor3 = Theme.colors.muted,
				ZIndex = 2,
			}),
			C.button({
				Name = "Join",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.new(0.62, -6, 0, 58),
				Color = Theme.colors.navy,
				Icon = "👥",
				Text = "JOIN GROUP",
				MaxTextSize = 24,
				ZIndex = 3,
				OnClick = join,
			}),
			C.button({
				Name = "Later",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 0, 1, 0),
				Size = UDim2.new(0.38, -6, 0, 58),
				Color = Theme.colors.slateLight,
				Text = "NOT NOW",
				MaxTextSize = 20,
				ZIndex = 3,
				OnClick = function()
					State.panel:set("none")
				end,
			}),
		},
	})
end
