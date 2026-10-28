--!strict
-- Daily reward calendar: 7 tiles (claimed / today / upcoming) and a big claim button.
-- Missing a day resets the streak, so the panel says so.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
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
						else C.label({
							Text = "💰",
							Size = UDim2.new(1, -16, 0.42, 0),
							Position = UDim2.new(0, 8, 0, 30),
							MaxTextSize = 48,
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
					C.label({
						Text = "✔",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.48),
						Size = UDim2.fromOffset(60, 60),
						MaxTextSize = 56,
						TextColor3 = Theme.colors.toxic,
						StrokeThickness = 4,
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
			CellSize = UDim2.fromOffset(112, 134),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}
	for day = 1, #Daily.rewards do
		table.insert(tiles, tile(day))
	end
	return C.panel({
		Title = "🎁 Daily Rewards",
		Accent = Theme.colors.danger,
		Size = UDim2.fromOffset(560, 480),
		IsOpen = Computed(function()
			return State.panel:get() == "daily"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.label({
				Text = Computed(function()
					local s = status()
					return if s.streak > 0
						then string.format("🔥 %d day streak! Come back tomorrow to keep it going.", s.streak)
						else "Log in every day for bigger rewards. Missing a day resets your streak!"
				end),
				Size = UDim2.new(1, 0, 0, 26),
				MaxTextSize = 18,
				TextColor3 = Theme.colors.cream,
				ZIndex = 2,
			}),
			New("Frame")({
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 36),
				Size = UDim2.new(1, 0, 0, 300),
				ZIndex = 2,
				[Children] = tiles,
			}),
			C.button({
				Name = "Claim",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(280, 58),
				Color = Theme.colors.gold,
				MaxTextSize = 26,
				ZIndex = 3,
				Pulse = Computed(function()
					return status().canClaim
				end),
				Disabled = Computed(function()
					return not status().canClaim
				end),
				Text = Computed(function()
					return if status().canClaim then "🎁 CLAIM DAY " .. status().day else "Come back tomorrow!"
				end),
				OnClick = function()
					Remotes.get("ClaimDaily"):FireServer()
				end,
			}),
		},
	})
end
