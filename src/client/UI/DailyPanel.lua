--!strict
-- Daily reward calendar: 7 tiles (claimed / today / upcoming) and a big claim button.
-- Missing a day resets the streak, so the panel says so. Under the calendar: the group reward
-- strip (until claimed) and, for VIP owners, the VIP strip with the daily 50 Gems.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Passes = require(ReplicatedStorage.Shared.Config.Passes)
local Daily = require(Shared.Config.Daily)
local Remotes = require(Shared.Remotes)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local function status()
	local snap = State.snapshot:get()
	return if snap and snap.daily then snap.daily else { day = 1, canClaim = false, streak = 0 }
end

local function tile(day: number)
	local reward = Daily.rewards[day]
	local big = day == #Daily.rewards
	local state = Computed(function()
		local s = status()
		if day < s.day or (day == s.day and not s.canClaim) then
			return "claimed"
		elseif day == s.day then
			return "today"
		end
		return "later"
	end)
	return New("Frame")({
		Name = "Day" .. day,
		LayoutOrder = day,
		BackgroundTransparency = 1,
		[Children] = {
			C.shadow(16, 4),
			New("Frame")({
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 1,
				[Children] = {
					New("UIStroke")({
						Thickness = Computed(function()
							return if state:get() == "today" then 4 else 2.5
						end),
						Color = Computed(function()
							return if state:get() == "today" then Theme.colors.gold else Theme.colors.slate
						end),
					}),
					C.pulse(
						Computed(function()
							return state:get() == "today"
						end),
						0.04
					),
					New("UIGradient")({
						Rotation = 90,
						Color = Computed(function()
							local s = state:get()
							if s == "today" then
								return ColorSequence.new(Color3.fromHex("#FFE58A"), Theme.colors.goldDark)
							elseif s == "claimed" then
								return ColorSequence.new(Theme.colors.toxicDark, Color3.fromHex("#25602A"))
							end
							return ColorSequence.new(
								if big then Theme.colors.purple else Theme.colors.slateLight,
								if big then Theme.colors.purpleDark else Theme.colors.slate
							)
						end),
					}),
					C.label({
						Text = "DAY " .. day,
						Position = UDim2.fromOffset(6, 6),
						Size = UDim2.new(1, -12, 0, 20),
						MaxTextSize = 18,
						ZIndex = 2,
					}),
					if reward.kind == "eggs"
						then Viewport.new({
							Build = function()
								return MutantModel.buildEgg(reward.egg, 1, {})
							end,
							Spin = big,
							Size = UDim2.new(1, -16, 0.5, 0),
							Position = UDim2.new(0, 8, 0, 28),
							ZIndex = 2,
						})
						else C.icon("coin", 40, nil, {
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.new(0.5, 0, 0, 36),
							ZIndex = 2,
						}),
					C.label({
						Text = reward.label,
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -6),
						Size = UDim2.new(1, -10, 0, 34),
						TextWrapped = true,
						MaxTextSize = 15,
						ZIndex = 2,
					}),
					C.icon("check", 48, nil, {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.48),
						ZIndex = 4,
						Visible = Computed(function()
							return state:get() == "claimed"
						end),
						ZIndex = 3,
					}),
				},
			}),
		},
	})
end

return function()
	local tiles: { any } = {
		New("UIGridLayout")({
			CellSize = UDim2.fromOffset(100, 100),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}
	for day = 1, #Daily.rewards do
		table.insert(tiles, tile(day))
	end
	return C.panel({
		Title = "Daily Rewards",
		Icon = "gift",
		Accent = Theme.colors.danger,
		Size = UDim2.fromOffset(560, 480),
		IsOpen = Computed(function()
			return State.panel:get() == "daily"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.icon("flame", 22, nil, {
				Position = UDim2.fromOffset(0, 2),
				ZIndex = 3,
				Visible = Computed(function()
					return status().streak > 0
				end),
			}),
			C.label({
				Text = Computed(function()
					local s = status()
					return if s.streak > 0
						then string.format("%d day streak! Claim the next one to keep it going.", s.streak)
						else "Log in every day for bigger rewards. Missing a day resets your streak!"
				end),
				Size = UDim2.new(1, 0, 0, 26),
				MaxTextSize = 18,
				TextColor3 = Theme.colors.cream,
				ZIndex = 2,
			}),
			New("Frame")({
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(1, 0, 0, 210),
				ZIndex = 2,
				[Children] = tiles,
			}),
			-- Strips under the calendar; hidden ones take no room.
			New("Frame")({
				Name = "Strips",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 252),
				Size = UDim2.new(1, 0, 0, 78),
				ZIndex = 2,
				[Children] = {
					New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
					-- Group reward (the codes replacement): join the Roblox group, claim once.
					New("Frame")({
						Name = "Group",
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 36),
						BackgroundColor3 = Theme.colors.panelHi,
						BorderSizePixel = 0,
						Visible = Computed(function()
							local snap = State.snapshot:get()
							-- Until they're in the group with the eggs claimed (leaving the group brings it back).
							return GameConfig.groupId ~= 0
								and snap ~= nil
								and not (snap.inGroup == true and snap.groupRewardClaimed == true)
						end),
						ZIndex = 2,
						[Children] = {
							C.stroke(Theme.colors.ink, 2.5),
							C.icon("group", 20, nil, {
								AnchorPoint = Vector2.new(0, 0.5),
								Position = UDim2.new(0, 10, 0.5, 0),
								ZIndex = 3,
							}),
							C.label({
								Text = (function()
									local parts = {
										string.format(
											"+%d%% CASH FOREVER",
											math.floor(GameConfig.groupCashBonus * 100 + 0.5)
										),
									}
									for eggId, count in GameConfig.groupReward.eggs or {} do
										table.insert(parts, count .. " " .. string.upper(eggId) .. " EGGS")
									end
									return "JOIN OUR GROUP: " .. table.concat(parts, " + ")
								end)(),
								Position = UDim2.fromOffset(38, 8),
								Size = UDim2.new(1, -178, 1, -16),
								TextXAlignment = Enum.TextXAlignment.Left,
								MaxTextSize = 15,
								ZIndex = 3,
							}),
							C.button({
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.new(1, -6, 0.5, 0),
								Size = UDim2.fromOffset(120, 34),
								Color = Theme.colors.navy,
								Text = "CLAIM",
								MaxTextSize = 16,
								ZIndex = 4,
								OnClick = function()
									Remotes.get("ClaimGroupReward"):FireServer()
								end,
							}),
						},
					}),
					-- VIP: 50 Gems every day (VIP owners only).
					New("Frame")({
						Name = "Vip",
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 36),
						BackgroundColor3 = Theme.colors.panelHi,
						BorderSizePixel = 0,
						Visible = Computed(function()
							local snap = State.snapshot:get()
							return snap ~= nil and snap.ownedPasses ~= nil and snap.ownedPasses.VIP == true
						end),
						ZIndex = 2,
						[Children] = {
							C.stroke(Theme.colors.gold, 2.5),
							C.icon("crown", 20, nil, {
								AnchorPoint = Vector2.new(0, 0.5),
								Position = UDim2.new(0, 10, 0.5, 0),
								ZIndex = 3,
							}),
							C.label({
								Text = string.format("VIP: %d GEMS EVERY DAY", Passes.VIP.dailyGems),
								Position = UDim2.fromOffset(38, 7),
								Size = UDim2.new(1, -178, 1, -14),
								TextXAlignment = Enum.TextXAlignment.Left,
								TextColor3 = Theme.colors.gold,
								MaxTextSize = 15,
								ZIndex = 3,
							}),
							C.button({
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.new(1, -6, 0.5, 0),
								Size = UDim2.fromOffset(120, 30),
								Color = Theme.colors.navy,
								MaxTextSize = 15,
								ZIndex = 4,
								Pulse = Computed(function()
									local snap = State.snapshot:get()
									return snap ~= nil and snap.vipGemsReady == true
								end),
								Disabled = Computed(function()
									local snap = State.snapshot:get()
									return not (snap ~= nil and snap.vipGemsReady == true)
								end),
								Text = Computed(function()
									local snap = State.snapshot:get()
									return if snap ~= nil and snap.vipGemsReady == true then "CLAIM" else "CLAIMED"
								end),
								Icon = Computed(function()
									local snap = State.snapshot:get()
									return if snap ~= nil and snap.vipGemsReady == true then "gem" else nil
								end),
								OnClick = function()
									Remotes.get("ClaimVipGems"):FireServer()
								end,
							}),
						},
					}),
				},
			}),
			C.button({
				Name = "Claim",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(280, 58),
				Color = Theme.colors.gold,
				Studs = true,
				MaxTextSize = 26,
				ZIndex = 3,
				Pulse = Computed(function()
					return status().canClaim
				end),
				Disabled = Computed(function()
					return not status().canClaim
				end),
				Text = Computed(function()
					if status().canClaim then
						return "CLAIM DAY " .. status().day
					end
					-- Rewards roll over at UTC midnight (DataService.dailyStatus): count down to it.
					local left = 86400 - (State.now:get() % 86400)
					return string.format("NEXT REWARD IN %dH %02dM", left // 3600, (left % 3600) // 60)
				end),
				OnClick = function()
					Remotes.get("ClaimDaily"):FireServer()
				end,
			}),
		},
	})
end
