--!strict
-- Sell Pad panel: every mutant in the bag with its current value, plus Sell All.
-- Values shown here are previews; the server recomputes the real price on sale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local Mutants = require(Shared.Config.Mutants)
local Valuation = require(Shared.Valuation)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

local function valueOf(item): number
	local snap = State.get()
	return Valuation.sellValue(item, if snap then snap.cashMultiplier else 1)
end

local function itemRow(itemId: string)
	local snap = State.get()
	local item = snap and snap.inventory[itemId]
	if not item then
		return nil
	end
	local mutant = Mutants[item.tier][item.rarity]
	local value = valueOf(item)
	local details = { item.rarity, string.format("x%.2f size", item.size) }
	for _, mutation in item.mutations do
		table.insert(details, mutation)
	end

	return New("Frame")({
		Name = itemId,
		-- Most valuable first.
		LayoutOrder = -math.floor(math.log10(math.max(value, 1)) * 1000),
		Size = UDim2.new(1, -8, 0, 64),
		BackgroundColor3 = Theme.colors.slateLight,
		[Children] = {
			C.corner(12),
			New("Frame")({
				Size = UDim2.new(0, 8, 1, -16),
				Position = UDim2.fromOffset(8, 8),
				BackgroundColor3 = Color3.fromHex(Rarities.info[item.rarity].color),
				[Children] = C.corner(4),
			}),
			C.label({
				Position = UDim2.fromOffset(24, 6),
				Size = UDim2.new(0.6, -24, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 22,
				Text = mutant.name,
			}),
			C.label({
				Position = UDim2.fromOffset(24, 34),
				Size = UDim2.new(0.6, -24, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromHex(Rarities.info[item.rarity].color),
				MaxTextSize = 16,
				Text = table.concat(details, " · "),
			}),
			C.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(130, 46),
				Color = Theme.colors.gold,
				Text = Format.cash(value),
				MaxTextSize = 20,
				OnClick = function()
					Remotes.get("Sell"):FireServer(itemId)
				end,
			}),
		},
	})
end

return function()
	local isOpen = Computed(function()
		return State.panel:get() == "sell"
	end)
	-- Map of id -> id so ForPairs only rebuilds rows for items that were added or removed.
	local itemIds = Computed(function()
		local snap = State.snapshot:get()
		local ids = {}
		if snap and isOpen:get() then
			for id in snap.inventory do
				ids[id] = id
			end
		end
		return ids
	end)
	local total = Computed(function()
		local snap = State.snapshot:get()
		local sum = 0
		if snap then
			for _, item in snap.inventory do
				sum += Valuation.sellValue(item, snap.cashMultiplier)
			end
		end
		return sum
	end)

	return C.panel({
		Title = "Sell Pad",
		IsOpen = isOpen,
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.button({
				Name = "SellAll",
				Size = UDim2.new(1, 0, 0, 52),
				Color = Theme.colors.gold,
				Text = Computed(function()
					return "Sell All for " .. Format.cash(total:get())
				end),
				Disabled = Computed(function()
					return total:get() <= 0
				end),
				OnClick = function()
					Remotes.get("SellAll"):FireServer()
				end,
			}),
			New("ScrollingFrame")({
				Position = UDim2.fromOffset(0, 62),
				Size = UDim2.new(1, 0, 1, -62),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				[Children] = {
					New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
					ForPairs(itemIds, function(id: string)
						return id, itemRow(id)
					end, Fusion.cleanup),
				},
			}),
		},
	})
end
