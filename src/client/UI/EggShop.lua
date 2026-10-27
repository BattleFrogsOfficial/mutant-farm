--!strict
-- Egg Shop panel. Every egg shows its odds before purchase (required for paid random items
-- once Gem eggs exist, and good practice for Cash eggs too). Locked tiers stay visible so
-- there is always one egg the player can't buy yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, Value = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value

local function oddsRow(tierId: string)
	local cells = {}
	for i, rarity in Rarities.order do
		cells[i] = C.label({
			LayoutOrder = i,
			Size = UDim2.new(0.2, -4, 1, 0),
			TextColor3 = Color3.fromHex(Rarities.info[rarity].color),
			MaxTextSize = 16,
			Text = rarity .. "\n" .. Format.percent(Eggs.tiers[tierId].odds[rarity]),
		})
	end
	table.insert(
		cells,
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		})
	)
	return cells
end

local function eggRow(tierId: string, order: number)
	local tier = Eggs.tiers[tierId]
	local showOdds = Value(false)
	local locked = Computed(function()
		local snap = State.snapshot:get()
		return not snap or snap.rebirths < tier.unlockRebirth
	end)
	local function cannotAfford(quantity: number)
		return Computed(function()
			return locked:get() or State.cash:get() < tier.cost * quantity
		end)
	end
	local function buy(quantity: number)
		return function()
			Remotes.get("BuyEgg"):FireServer(tierId, quantity)
		end
	end

	return New("Frame")({
		Name = tierId,
		LayoutOrder = order,
		Size = Computed(function()
			return UDim2.new(1, -8, 0, if showOdds:get() then 132 else 84)
		end),
		BackgroundColor3 = Theme.colors.slateLight,
		[Children] = {
			C.corner(14),
			New("Frame")({
				Name = "Swatch",
				Position = UDim2.fromOffset(10, 12),
				Size = UDim2.fromOffset(48, 60),
				BackgroundColor3 = Color3.fromHex(tier.color),
				[Children] = { New("UICorner")({ CornerRadius = UDim.new(0.5, 0) }), C.stroke() },
			}),
			C.label({
				Position = UDim2.fromOffset(70, 8),
				Size = UDim2.new(0.45, -70, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 26,
				Text = tier.name,
			}),
			C.label({
				Position = UDim2.fromOffset(70, 42),
				Size = UDim2.new(0.45, -70, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.muted,
				MaxTextSize = 18,
				Text = Computed(function()
					if locked:get() then
						return string.format("Unlocks at Rebirth %d", tier.unlockRebirth)
					end
					return string.format(
						"%s  ·  sells from %s",
						Format.duration(tier.growTime),
						Format.cash(tier.baseValue)
					)
				end),
			}),
			C.button({
				Name = "Odds",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -236, 0, 18),
				Size = UDim2.fromOffset(64, 48),
				Color = Theme.colors.purple,
				Text = "Odds",
				MaxTextSize = 18,
				OnClick = function()
					showOdds:set(not showOdds:get(false))
				end,
			}),
			C.button({
				Name = "Buy1",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -118, 0, 18),
				Size = UDim2.fromOffset(110, 48),
				Text = Computed(function()
					return if locked:get() then "Locked" else "Buy " .. Format.cash(tier.cost)
				end),
				MaxTextSize = 20,
				Disabled = cannotAfford(1),
				OnClick = buy(1),
			}),
			C.button({
				Name = "Buy5",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 18),
				Size = UDim2.fromOffset(100, 48),
				Text = "x5",
				MaxTextSize = 20,
				Disabled = cannotAfford(5),
				OnClick = buy(5),
			}),
			New("Frame")({
				Name = "OddsRow",
				Visible = showOdds,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 84),
				Size = UDim2.new(1, -20, 0, 40),
				[Children] = oddsRow(tierId),
			}),
		},
	})
end

return function()
	local rows = {}
	for i, tierId in Eggs.order do
		rows[i] = eggRow(tierId, i)
	end
	table.insert(rows, New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }))

	return C.panel({
		Title = "Egg Shop",
		IsOpen = Computed(function()
			return State.panel:get() == "shop"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = New("ScrollingFrame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			[Children] = rows,
		}),
	})
end
