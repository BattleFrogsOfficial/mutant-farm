--!strict
-- Screen layer for the hatch cutscene: white flash, Skip buttons, and the reveal card that
-- slides up once the mutant is standing on the stage. HatchController drives it through State.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, Spring, ForValues =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Spring, Fusion.ForValues

local _ = Shared

return function()
	local card = State.hatchCard
	local shown = Computed(function()
		return card:get() ~= nil
	end)
	local slide = Spring(
		Computed(function()
			return if shown:get() then 0 else 1
		end),
		22,
		0.75
	)
	local color = Computed(function()
		local c = card:get()
		return if c then c.color else Theme.colors.white
	end)

	return {
		-- Full-screen flash between the farm and the stage.
		New("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = Computed(function()
				return 1 - State.hatchFlash:get()
			end),
			Visible = Computed(function()
				return State.hatchFlash:get() > 0.001
			end),
			ZIndex = 50,
		}),
		New("Frame")({
			Name = "Skips",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 16),
			Size = UDim2.fromOffset(330, 56),
			BackgroundTransparency = 1,
			Visible = State.hatching,
			ZIndex = 40,
			[Children] = {
				New("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					Padding = UDim.new(0, 10),
				}),
				C.button({
					Name = "SkipAll",
					Text = Computed(function()
						return string.format("Skip all (%d)", State.hatchQueue:get() + 1)
					end),
					Size = UDim2.fromOffset(170, 52),
					Color = Theme.colors.slateLight,
					MaxTextSize = 20,
					Visible = Computed(function()
						return State.hatchQueue:get() > 0
					end),
					OnClick = function()
						State.hatchAction("skipAll")
					end,
				}),
				C.button({
					Name = "Skip",
					Text = "Skip ⏭",
					Size = UDim2.fromOffset(130, 52),
					Color = Theme.colors.slateLight,
					MaxTextSize = 20,
					OnClick = function()
						State.hatchAction("skip")
					end,
				}),
			},
		}),
		-- Reveal card.
		New("Frame")({
			Name = "RevealCard",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = Computed(function()
				return UDim2.new(0.5, 0, 1, -24 + slide:get() * 320)
			end),
			Size = UDim2.fromOffset(560, 210),
			BackgroundColor3 = Theme.colors.slate,
			Visible = Computed(function()
				return shown:get() or slide:get() < 0.99
			end),
			ZIndex = 40,
			[Children] = {
				C.corner(24),
				New("UIStroke")({ Color = color, Thickness = 5 }),
				New("Frame")({
					Name = "NewBadge",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0, 0),
					Size = UDim2.fromOffset(260, 36),
					BackgroundColor3 = Theme.colors.toxic,
					Visible = Computed(function()
						local c = card:get()
						return c ~= nil and c.isNew
					end),
					ZIndex = 42,
					[Children] = {
						C.round(),
						C.stroke(Theme.colors.slate, 3),
						C.label({
							Text = "NEW! Added to your Almanac",
							Size = UDim2.new(1, -16, 1, -6),
							Position = UDim2.fromOffset(8, 3),
							MaxTextSize = 20,
							ZIndex = 43,
						}),
					},
				}),
				C.label({
					Name = "Rarity",
					Position = UDim2.fromOffset(20, 24),
					Size = UDim2.new(1, -40, 0, 30),
					MaxTextSize = 28,
					TextColor3 = color,
					ZIndex = 41,
					Text = Computed(function()
						local c = card:get()
						return if c then c.rarity:upper() else ""
					end),
				}),
				C.label({
					Name = "Name",
					Position = UDim2.fromOffset(20, 54),
					Size = UDim2.new(1, -40, 0, 54),
					MaxTextSize = 52,
					StrokeThickness = 4,
					ZIndex = 41,
					Text = Computed(function()
						local c = card:get()
						return if c then c.name else ""
					end),
				}),
				New("Frame")({
					Name = "Tags",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(20, 112),
					Size = UDim2.new(1, -40, 0, 30),
					ZIndex = 41,
					[Children] = {
						New("UIListLayout")({
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							Padding = UDim.new(0, 8),
						}),
						ForValues(
							Computed(function()
								local c = card:get()
								return if c then c.tags else {}
							end),
							function(tag: string)
								return New("Frame")({
									Size = UDim2.fromOffset(0, 28),
									AutomaticSize = Enum.AutomaticSize.X,
									BackgroundColor3 = Theme.colors.slateLight,
									ZIndex = 41,
									[Children] = {
										C.round(),
										New("UIPadding")({
											PaddingLeft = UDim.new(0, 12),
											PaddingRight = UDim.new(0, 12),
										}),
										New("TextLabel")({
											BackgroundTransparency = 1,
											AutomaticSize = Enum.AutomaticSize.X,
											Size = UDim2.fromScale(0, 1),
											Font = Theme.font,
											TextSize = 18,
											TextColor3 = Theme.colors.white,
											Text = tag,
											ZIndex = 42,
										}),
									},
								})
							end,
							Fusion.cleanup
						),
					},
				}),
				C.label({
					Name = "Value",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 20, 1, -14),
					Size = UDim2.new(0.6, -20, 0, 44),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theme.colors.toxic,
					MaxTextSize = 38,
					StrokeThickness = 3,
					ZIndex = 41,
					Text = Computed(function()
						local c = card:get()
						return if c then "Worth " .. c.value else ""
					end),
				}),
				C.button({
					Name = "Continue",
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -16, 1, -14),
					Size = UDim2.fromOffset(170, 56),
					Color = Theme.colors.toxic,
					Text = "Nice! ▶",
					MaxTextSize = 24,
					OnClick = function()
						State.hatchAction("next")
					end,
				}),
			},
		}),
	}
end
