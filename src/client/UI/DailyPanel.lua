--!strict
-- Daily reward calendar in the shop's chrome: a card per day like the Egg Shop's (day label, the
-- reward as the real egg model, a coin stack for Cash, the gem glyph for Gems). Claimed cards get a
-- green border and a check, today's a pulsing gold border and a CLAIM button, later days are dimmed
-- with a lock; the Day 7 Toxic egg card is wider. Missing a day resets the streak, so the panel
-- says so; the bottom button claims, or counts down to the next reward. Under the calendar: the group reward
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

-- Card sizes (design px): six 88 wide and the Day 7 card wider, 12 apart (room for the 4 px
-- borders) = the 728 content width.
local CARD_W, BIG_W, CARD_H, CARD_GAP = 88, 128, 196, 12

-- The reward's art: the real egg model, a stack of coins for Cash, the gem glyph for Gems.
local function art(reward: any, big: boolean)
	if reward.kind == "eggs" then
		return Viewport.new({
			Build = function()
				return MutantModel.buildEgg(reward.egg, 1, {})
			end,
			Spin = big,
			Size = UDim2.new(1, -12, 0, 72),
			Position = UDim2.fromOffset(6, 28),
			ZIndex = 3,
		})
	end
	local glyph = if reward.kind == "gems" then "gem" else "coin"
	local stack: { any } = {}
	local n = if reward.kind == "gems" then 1 else 3
	for i = 1, n do
		-- Bottom coin first, each next one drawn over it a little higher.
		table.insert(
			stack,
			C.icon(glyph, 40, nil, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, (i - 2) * 6 * (n - 1) / 2, 0, 96 - (i - 1) * 12),
				ZIndex = 3 + i,
			})
		)
	end
	return New("Frame")({
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		[Children] = stack,
	})
end

-- The two reward lines under the art: the amount (a number, 16 px) and what it is (14 px).
local function rewardLines(reward: any): (string, string)
	if reward.kind == "eggs" then
		return "x" .. reward.count, string.upper(reward.egg)
	elseif reward.kind == "gems" then
		return "x" .. reward.count, "GEMS"
	end
	return "$ x" .. reward.minutes, "MINUTES"
end

local function card(day: number)
	local reward = Daily.rewards[day]
	local big = day == #Daily.rewards
	local state = Computed(function()
		local s = status()
		if day < s.day or (day == s.day and not s.canClaim) then
			return "claimed"
		elseif day == s.day then
			return "today"
		end
		return "locked"
	end)
	local amount, what = rewardLines(reward)
	return New("Frame")({
		Name = "Day" .. day,
		LayoutOrder = day,
		Size = UDim2.fromOffset(if big then BIG_W else CARD_W, CARD_H),
		BackgroundTransparency = 1,
		[Children] = {
			C.shadow(),
			New("Frame")({
				Name = "Face",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = if big then Theme.colors.purpleDark else Theme.colors.panelHi,
				BorderSizePixel = 0,
				ZIndex = 1,
				[Children] = {
					C.bevel(2),
					-- Border: green once claimed, a pulsing gold today, ink otherwise.
					New("UIStroke")({
						Thickness = Computed(function()
							return if state:get() == "locked" then 3 else 4
						end),
						Color = Computed(function()
							local st = state:get()
							if st == "claimed" then
								return Theme.colors.toxic
							elseif st == "today" then
								return Theme.colors.gold
							end
							return Theme.colors.ink
						end),
						Transparency = Computed(function()
							if state:get() ~= "today" then
								return 0
							end
							return 0.55 * math.abs(math.sin(State.clock:get() * math.pi / 2))
						end),
					}),
					C.label({
						Name = "Day",
						Text = "DAY " .. day,
						Position = UDim2.fromOffset(4, 6),
						Size = UDim2.new(1, -8, 0, 20),
						TextScaled = false,
						TextSize = 16,
						TextColor3 = Computed(function()
							return if state:get() == "today" then Theme.colors.gold else Theme.colors.white
						end),
						ZIndex = 4,
					}),
					art(reward, big),
					C.label({
						Name = "Amount",
						Text = amount,
						Position = UDim2.fromOffset(2, 104),
						Size = UDim2.new(1, -4, 0, 20),
						TextScaled = false,
						TextSize = 16,
						ZIndex = 4,
					}),
					C.label({
						Name = "What",
						Text = what,
						Position = UDim2.fromOffset(2, 124),
						Size = UDim2.new(1, -4, 0, 18),
						TextScaled = false,
						TextSize = 14,
						TextColor3 = Theme.colors.cream,
						StrokeThickness = 0,
						ZIndex = 4,
					}),
					-- Bottom of the card: CLAIM today, a check once claimed, a lock while ahead.
					C.button({
						Name = "Claim",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, -2, 1, -10),
						Size = UDim2.new(1, -16, 0, 38),
						Color = Theme.colors.navy,
						Text = "CLAIM",
						MaxTextSize = 16,
						ZIndex = 5,
						Visible = Computed(function()
							return state:get() == "today"
						end),
						OnClick = function()
							Remotes.get("ClaimDaily"):FireServer()
						end,
					}),
					C.icon("check", 32, nil, {
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -12),
						ZIndex = 5,
						Visible = Computed(function()
							return state:get() == "claimed"
						end),
					}),
					C.icon("lock", 24, nil, {
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -16),
						ZIndex = 5,
						Visible = Computed(function()
							return state:get() == "locked"
						end),
					}),
					-- Days ahead: dimmed under a panel-colored veil.
					New("Frame")({
						Name = "Veil",
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Theme.colors.panel,
						BackgroundTransparency = 0.45,
						BorderSizePixel = 0,
						ZIndex = 6,
						Visible = Computed(function()
							return state:get() == "locked"
						end),
					}),
				},
			}),
		},
	})
end

return function()
	local cards: { any } = {
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}
	for day = 1, #Daily.rewards do
		table.insert(cards, card(day))
	end
	return C.panel({
		Title = "Daily Rewards",
		Icon = "gift",
		Accent = Theme.colors.danger,
		Size = UDim2.fromOffset(760, 480),
		IsOpen = Computed(function()
			return State.panel:get() == "daily"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.iconText({
				Name = "Streak",
				Icon = "flame",
				IconSize = 22,
				Text = Computed(function()
					local s = status()
					return if s.streak > 0
						then string.format("%d DAY STREAK! Claim the next one to keep it going.", s.streak)
						else "Log in every day for bigger rewards. Missing a day resets your streak!"
				end),
				TextSize = 16,
				TextColor3 = Theme.colors.cream,
				Size = UDim2.new(1, 0, 0, 26),
				ZIndex = 3,
			}),
			New("Frame")({
				Name = "Cards",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(1, 0, 0, CARD_H),
				ZIndex = 2,
				[Children] = cards,
			}),
			-- Strips under the calendar; hidden ones take no room.
			New("Frame")({
				Name = "Strips",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 244),
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
								MaxTextSize = 16,
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
								MaxTextSize = 16,
								ZIndex = 3,
							}),
							C.button({
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.new(1, -6, 0.5, 0),
								Size = UDim2.fromOffset(120, 30),
								Color = Theme.colors.navy,
								MaxTextSize = 16,
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
				Color = Theme.colors.navy,
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
