--!strict
-- Sell Pad panel: the most valuable mutants in the bag (with 3D thumbnails), plus Sell All.
-- Each row has a pin toggle: pinned mutants always stand in the pen and Sell All skips them.
-- Values shown are previews; the server recomputes the real price on sale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Rarities = require(Shared.Config.Rarities)
local GameConfig = require(Shared.Config.Game)
local Eggs = require(Shared.Config.Eggs)
local Pen = require(Shared.Pen)
local Valuation = require(Shared.Valuation)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

-- Rows are capped so a full bag doesn't build 200 3D thumbnails; Sell All still sells everything.
local MAX_ROWS = 60

local function valueOf(item): number
	local snap = State.get()
	return Valuation.sellValue(item, if snap then snap.cashMultiplier else 1)
end

local function itemRow(itemId: string, order: any)
	local snap = State.get()
	local item = snap and snap.inventory[itemId]
	if not item then
		return nil
	end
	local species = MutantModel.species(item)
	local value = valueOf(item)
	local rarityColor = Color3.fromHex(Rarities.info[item.rarity].color)
	local details = { item.rarity, string.format("x%.2f size", item.size) }
	for _, mutation in MutantModel.sortedMutations(item.mutations) do
		table.insert(details, mutation:upper())
	end
	local pinned = Computed(function()
		local s = State.snapshot:get()
		local it = s and s.inventory[itemId]
		return it ~= nil and it.pinned == true
	end)

	return New("Frame")({
		Name = itemId,
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, 74),
		BackgroundColor3 = Theme.colors.slateLight,
		ZIndex = 10,
		[Children] = {
			C.stroke(rarityColor, 2.5),
			New("Frame")({
				Name = "Thumb",
				Position = UDim2.fromOffset(6, 5),
				Size = UDim2.fromOffset(64, 64),
				BackgroundColor3 = Theme.colors.slate,
				ZIndex = 10,
				[Children] = {
					Viewport.new({
						Build = function()
							return MutantModel.build(item)
						end,
						ZIndex = 11,
					}),
				},
			}),
			C.label({
				Position = UDim2.fromOffset(80, 8),
				Size = UDim2.new(1, -290, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				TextColor3 = rarityColor,
				Text = species.name,
				ZIndex = 11,
			}),
			C.label({
				Position = UDim2.fromOffset(80, 40),
				Size = UDim2.new(1, -290, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 16,
				Text = Computed(function()
					local text = table.concat(details, " · ")
					return if pinned:get() then "IN PEN · " .. text else text
				end),
				ZIndex = 11,
			}),
			-- Pin toggle: keeps this mutant in the pen (gold outline while pinned).
			C.button({
				Name = "Pin",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -152, 0.5, 0),
				Size = UDim2.fromOffset(52, 52),
				Color = Theme.colors.navy,
				Text = "",
				Icon = "pin",
				IconSize = 26,
				MaxTextSize = 22,
				Selected = pinned,
				OnClick = function()
					local s = State.get()
					local on = not pinned:get(false)
					if on and s and not Pen.canPin(s.inventory, s.penCapacity or GameConfig.penDisplayCount) then
						State.toast(
							string.format(
								"Your pen holds %d. Unpin one first!",
								s and s.penCapacity or GameConfig.penDisplayCount
							),
							"info"
						)
						return
					end
					Remotes.get("Pin"):FireServer(itemId, on)
				end,
			}),
			C.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(136, 52),
				Color = Theme.colors.navy,
				Icon = "coin",
				Text = Format.cash(value),
				MaxTextSize = 20,
				Silent = true,
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
	-- id -> sort position; only the top MAX_ROWS by value, and nothing while closed.
	local order = Computed(function()
		local snap = State.snapshot:get()
		local out = {}
		if not snap or not isOpen:get() then
			return out
		end
		local list = {}
		for id, item in snap.inventory do
			table.insert(list, { id = id, value = Valuation.sellValue(item, 1), n = tonumber(id) or 0 })
		end
		table.sort(list, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			return a.n < b.n
		end)
		for i = 1, math.min(#list, MAX_ROWS) do
			out[list[i].id] = i
		end
		return out
	end)
	local rows = Computed(function()
		local out = {}
		for id in order:get() do
			out[id] = id
		end
		return out
	end)
	-- Sell All sells everything except pinned mutants.
	local summary = Computed(function()
		local snap = State.snapshot:get()
		local sum, count, pinned = 0, 0, 0
		if snap then
			for _, item in snap.inventory do
				if item.pinned then
					pinned += 1
				else
					sum += Valuation.sellValue(item, snap.cashMultiplier)
					count += 1
				end
			end
		end
		return { sum = sum, count = count, pinned = pinned }
	end)

	return C.panel({
		Title = "Sell Pad",
		Icon = "bag",
		Accent = Theme.colors.goldDark,
		Size = UDim2.fromOffset(600, 470),
		IsOpen = isOpen,
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.button({
				Name = "SellAll",
				Size = UDim2.new(1, 0, 0, 62),
				Color = Theme.colors.navy,
				Icon = "bag",
				MaxTextSize = 24,
				Text = Computed(function()
					local s = summary:get()
					if s.count > 0 then
						return string.format("Sell all %d for %s", s.count, Format.cash(s.sum))
							.. (if s.pinned > 0 then string.format(" (%d pinned stay)", s.pinned) else "")
					end
					return if s.pinned > 0 then "Only pinned mutants left" else "Your bag is empty"
				end),
				Disabled = Computed(function()
					return summary:get().count == 0
				end),
				Silent = true,
				OnClick = function()
					Remotes.get("SellAll"):FireServer()
				end,
			}),
			New("ScrollingFrame")({
				Position = UDim2.fromOffset(0, 74),
				Size = UDim2.new(1, 0, 1, -74),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ZIndex = 10,
				[Children] = {
					New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
					C.padding(4), -- room for row outlines inside the scroll clip
					-- Keyed id -> id so selling one item doesn't rebuild every row below it;
					-- positions come from `order` instead.
					ForPairs(rows, function(id: string)
						return id,
							itemRow(
								id,
								Computed(function()
									return order:get()[id] or 999
								end)
							)
					end, Fusion.cleanup),
				},
			}),
		},
	})
end
