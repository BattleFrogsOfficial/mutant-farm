--!strict
-- Always-on HUD: Cash (top), egg hotbar (bottom), Water / Harvest buttons (bottom right).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

local function cashPill()
	return New("Frame")({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(240, 52),
		BackgroundColor3 = Theme.colors.slate,
		[Children] = {
			C.corner(26),
			C.stroke(Theme.colors.toxic, 3),
			C.label({
				Size = UDim2.new(1, -24, 1, -12),
				Position = UDim2.fromOffset(12, 6),
				TextColor3 = Theme.colors.toxic,
				MaxTextSize = 36,
				Text = Computed(function()
					return Format.cash(State.cash:get())
				end),
			}),
		},
	})
end

local function eggBar()
	local eggs = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.eggs else {}
	end)
	local hasEggs = Computed(function()
		return next(eggs:get()) ~= nil
	end)

	return New("Frame")({
		Name = "EggBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.6, 0, 0, 96),
		BackgroundTransparency = 1,
		[Children] = {
			C.label({
				Size = UDim2.new(1, 0, 0, 24),
				MaxTextSize = 20,
				Text = Computed(function()
					return if hasEggs:get()
						then "Tap an empty plot to plant your selected egg"
						else "Out of eggs! Visit the Egg Shop in the middle"
				end),
			}),
			New("Frame")({
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 28),
				Size = UDim2.new(1, 0, 0, 64),
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					ForPairs(eggs, function(eggId: string, count: number)
						local tier = Eggs.tiers[eggId]
						return eggId,
							C.button({
								Name = eggId,
								LayoutOrder = table.find(Eggs.order, eggId),
								Size = UDim2.fromOffset(130, 60),
								Color = Color3.fromHex(tier.color),
								Text = string.format("%s x%d", eggId, count),
								OnClick = function()
									State.selectedEgg:set(eggId)
								end,
								Selected = Computed(function()
									return State.selectedEgg:get() == eggId
								end),
							})
					end, Fusion.cleanup),
				},
			}),
		},
	})
end

local function actionButtons()
	local watering = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and State.now:get() < snap.wateredUntil
	end)
	return New("Frame")({
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(170, 132),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 10),
			}),
			C.button({
				Name = "Harvest",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(170, 56),
				Color = Theme.colors.gold,
				Text = Computed(function()
					return string.format("Harvest (%d)", State.readyCount:get())
				end),
				Disabled = Computed(function()
					return State.readyCount:get() == 0
				end),
				OnClick = function()
					Remotes.get("HarvestAll"):FireServer()
				end,
			}),
			C.button({
				Name = "Water",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(170, 56),
				Color = Theme.colors.water,
				Disabled = watering,
				Text = Computed(function()
					local snap = State.snapshot:get()
					if snap and watering:get() then
						return "2x " .. Format.duration(snap.wateredUntil - State.now:get())
					end
					return "Water 2x"
				end),
				OnClick = function()
					Remotes.get("Water"):FireServer()
				end,
			}),
		},
	})
end

local function bagCounter()
	return C.label({
		Name = "Bag",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(170, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Text = Computed(function()
			local snap = State.snapshot:get()
			if not snap then
				return ""
			end
			local n = 0
			for _ in snap.inventory do
				n += 1
			end
			return string.format("Bag %d/%d", n, snap.inventoryCap)
		end),
	})
end

return function()
	return { cashPill(), eggBar(), actionButtons(), bagCounter() }
end
