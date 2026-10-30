--!strict
-- Tapping a patch you can't afford yet opens this instead of an error: two ways forward.
--   EARN IT     how close you are (progress bar) and roughly how long at your pen income
--   +10 SLOTS   the Plot Slots pass (hidden once owned)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Passes = require(Shared.Config.Passes)
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Format)
local State = require(script.Parent.Parent.State)
local Purchase = require(script.Parent.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local function card(props: { [string]: any })
	return New("Frame")({
		Name = props.Name,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		Visible = props.Visible,
		ZIndex = 3,
		[Children] = {
			C.shadow(),
			New("Frame")({
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = props.Color,
				ZIndex = 1,
				[Children] = { C.stroke(Theme.colors.ink, 3), C.bevel(2, 0.8), props.Children },
			}),
		},
	})
end

return function()
	local price = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.nextSlotCost or 0 else 0
	end)
	local progress = Computed(function()
		local p = price:get()
		return if p > 0 then math.clamp(State.cash:get() / p, 0, 1) else 1
	end)
	-- Also true when the pass wouldn't give all ten any more: then only the earn-it card shows.
	local ownsPass = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil
			and (
				(snap.ownedPasses ~= nil and snap.ownedPasses.PlotSlots10 == true)
				or snap.slotCount > Upgrades.slots.max - 10
			)
	end)
	return C.panel({
		Title = "New Soil Patch",
		Icon = "sprout",
		Accent = Theme.colors.toxicDark,
		Size = UDim2.fromOffset(560, 330),
		IsOpen = Computed(function()
			return State.panel:get() == "slotOffer"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			card({
				Name = "Earn",
				Position = UDim2.fromOffset(0, 4),
				Size = Computed(function()
					return if ownsPass:get() then UDim2.new(1, -6, 0, 220) else UDim2.new(0.5, -10, 0, 220)
				end),
				Color = Theme.colors.panelHi,
				Children = {
					C.label({
						Text = "EARN IT",
						Position = UDim2.fromOffset(14, 12),
						Size = UDim2.new(1, -28, 0, 22),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 20,
						ZIndex = 2,
					}),
					C.label({
						Text = Computed(function()
							return Format.cash(price:get())
						end),
						Position = UDim2.fromOffset(14, 42),
						Size = UDim2.new(1, -28, 0, 40),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Theme.colors.toxic,
						MaxTextSize = 36,
						ZIndex = 2,
					}),
					New("Frame")({
						Name = "Bar",
						Position = UDim2.fromOffset(14, 96),
						Size = UDim2.new(1, -28, 0, 22),
						BackgroundColor3 = Theme.colors.ink,
						BorderSizePixel = 0,
						ZIndex = 2,
						[Children] = {
							New("Frame")({
								BorderSizePixel = 0,
								BackgroundColor3 = Theme.colors.toxicDark,
								Size = Computed(function()
									return UDim2.fromScale(progress:get(), 1)
								end),
								ZIndex = 3,
							}),
							C.label({
								Text = Computed(function()
									return string.format(
										"%s / %s",
										Format.cash(State.cash:get()),
										Format.cash(price:get())
									)
								end),
								Size = UDim2.new(1, -10, 1, -6),
								Position = UDim2.fromOffset(5, 3),
								MaxTextSize = 16,
								ZIndex = 4,
							}),
						},
					}),
					C.label({
						Text = Computed(function()
							local snap = State.snapshot:get()
							local short = math.max(0, price:get() - State.cash:get())
							local perMinute = if snap then snap.incomePerMinute or 0 else 0
							if short <= 0 then
								return "You can afford it! Tap the patch."
							elseif perMinute > 0 then
								return string.format(
									"~ %d min of pen income, or hatch & sell",
									math.ceil(short / perMinute)
								)
							end
							return "Hatch and sell mutants to get there"
						end),
						Position = UDim2.fromOffset(14, 128),
						Size = UDim2.new(1, -28, 0, 40),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						TextColor3 = Theme.colors.cream,
						StrokeThickness = 0,
						MaxTextSize = 15,
						ZIndex = 2,
					}),
					C.button({
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -10),
						Size = UDim2.new(1, -28, 0, 44),
						Color = Theme.colors.slateLight,
						Text = "KEEP FARMING",
						MaxTextSize = 18,
						ZIndex = 3,
						OnClick = function()
							State.panel:set("none")
						end,
					}),
				},
			}),
			card({
				Name = "Pass",
				Position = UDim2.new(0.5, 4, 0, 4),
				Size = UDim2.new(0.5, -10, 0, 220),
				Color = Theme.colors.navy,
				Visible = Computed(function()
					return not ownsPass:get()
				end),
				Children = {
					C.label({
						Text = "OR SKIP AHEAD",
						Position = UDim2.fromOffset(14, 12),
						Size = UDim2.new(1, -28, 0, 22),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxTextSize = 20,
						ZIndex = 2,
					}),
					C.iconText({
						Icon = "sprout",
						IconSize = 32,
						Text = "+10 PATCHES",
						Align = "Left",
						Position = UDim2.fromOffset(14, 42),
						Size = UDim2.new(1, -28, 0, 40),
						TextColor3 = Theme.colors.gold,
						TextSize = 28,
						ZIndex = 2,
					}),
					C.label({
						Text = "Ten extra patches right now, forever. Survive every rebirth.",
						Position = UDim2.fromOffset(14, 92),
						Size = UDim2.new(1, -28, 0, 60),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextWrapped = true,
						TextColor3 = Theme.colors.cream,
						StrokeThickness = 0,
						MaxTextSize = 15,
						ZIndex = 2,
					}),
					C.button({
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -10),
						Size = UDim2.new(1, -28, 0, 44),
						Color = Theme.colors.spend,
						Text = "R$ " .. Passes.PlotSlots10.price,
						MaxTextSize = 20,
						Pulse = true,
						ZIndex = 3,
						OnClick = function()
							Purchase.pass("PlotSlots10")
						end,
					}),
				},
			}),
		},
	})
end
