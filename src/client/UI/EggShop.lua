--!strict
-- Egg Shop: a grid of egg cards with live 3D eggs. Three clear states per card:
--   available  - full color, green Buy buttons
--   too pricey - full color, grey Buy buttons and "Earn $X more" in gold (never red)
--   locked     - a small card in the row underneath: padlock, name, "REBIRTH N"
-- Every card has an Odds view (required for paid random items once Gem eggs exist).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, Value = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value

local function oddsList(tierId: string)
	local rows: { any } = {
		New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	}
	for i, rarity in Rarities.order do
		table.insert(
			rows,
			New("Frame")({
				LayoutOrder = i,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 22),
				[Children] = {
					C.label({
						Text = rarity,
						Size = UDim2.new(0.62, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Color3.fromHex(Rarities.info[rarity].color),
						MaxTextSize = 18,
					}),
					C.label({
						Text = Format.percent(Eggs.tiers[tierId].odds[rarity]),
						Position = UDim2.fromScale(0.62, 0),
						Size = UDim2.new(0.38, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Right,
						MaxTextSize = 18,
					}),
				},
			})
		)
	end
	return rows
end

local function eggCard(tierId: string, order: number, visible: any)
	local tier = Eggs.tiers[tierId]
	local showOdds = Value(false)
	-- `locked` and the shortfalls read State.snapshot directly inside whichever Computed calls them,
	-- not through intermediate Computeds. Fusion 0.2 can't order a dependency it first discovers
	-- mid-update: the card's text first read only `locked` (no snapshot yet), then read a stale
	-- shortfall when the snapshot arrived, and kept showing "Earn $50 more" with plenty of Cash.
	local locked = {
		get = function(_self): boolean
			local snap = State.snapshot:get()
			return not snap or snap.rebirths < tier.unlockRebirth
		end,
	}
	local function short(quantity: number)
		return {
			get = function(_self): number
				local snap = State.snapshot:get()
				return math.max(0, tier.cost * quantity - (if snap then snap.cash else 0))
			end,
		}
	end
	local short1 = short(1)
	local short5 = short(5)

	return New("Frame")({
		Name = tierId,
		LayoutOrder = order,
		Visible = visible,
		Size = UDim2.fromOffset(186, 228),
		BackgroundColor3 = Computed(function()
			return if locked:get() then Theme.colors.slate else Theme.colors.slateLight
		end),
		[Children] = {
			C.stroke(
				Computed(function()
					return if locked:get() then Theme.colors.locked else Color3.fromHex(tier.color)
				end),
				3
			),
			-- Egg preview, built once (big cards only show unlocked tiers; locked ones use the small
			-- row). Not a Computed: it would rebuild on every snapshot.
			Viewport.new({
				Build = function()
					return MutantModel.buildEgg(tierId, 1, {})
				end,
				Spin = true,
				Size = UDim2.fromOffset(110, 104),
				Position = UDim2.new(0.5, 0, 0, 8),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = 11,
			}),
			New("Frame")({
				Name = "LockLayer",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = Computed(function()
					return locked:get()
				end),
				ZIndex = 12,
				[Children] = C.padlock({
					Size = UDim2.fromOffset(40, 48),
					Position = UDim2.new(0.5, 0, 0, 34),
					AnchorPoint = Vector2.new(0.5, 0),
					ZIndex = 12,
				}),
			}),
			C.label({
				Text = tier.name,
				Position = UDim2.fromOffset(8, 112),
				Size = UDim2.new(1, -16, 0, 28),
				MaxTextSize = 24,
				ZIndex = 11,
				TextColor3 = Computed(function()
					return if locked:get() then Theme.colors.muted else Theme.colors.white
				end),
			}),
			C.label({
				Position = UDim2.fromOffset(8, 140),
				Size = UDim2.new(1, -16, 0, 20),
				MaxTextSize = 16,
				ZIndex = 11,
				TextColor3 = Computed(function()
					if locked:get() then
						return Theme.colors.gold
					elseif short1:get() > 0 or short5:get() > 0 then
						return Theme.colors.gold
					end
					return Theme.colors.muted
				end),
				Text = Computed(function()
					if locked:get() then
						return string.format("🔒 Rebirth %d to unlock", tier.unlockRebirth)
					elseif short1:get() > 0 then
						return "Earn " .. Format.cash(short1:get()) .. " more"
					elseif short5:get() > 0 then
						return "Earn " .. Format.cash(short5:get()) .. " more for x5"
					end
					return string.format(
						"Grows %s · sells %s+",
						Format.duration(tier.growTime),
						Format.cash(tier.baseValue)
					)
				end),
			}),
			-- Buy row (hidden while locked).
			New("Frame")({
				Name = "BuyRow",
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 8, 1, -60),
				Size = UDim2.new(1, -16, 0, 52),
				Visible = Computed(function()
					return not locked:get()
				end),
				ZIndex = 11,
				[Children] = {
					C.button({
						Name = "Buy1",
						Size = UDim2.new(0.62, -4, 1, 0),
						Text = Format.cash(tier.cost),
						MaxTextSize = 22,
						Disabled = Computed(function()
							return short1:get() > 0
						end),
						OnClick = function()
							Remotes.get("BuyEgg"):FireServer(tierId, 1)
						end,
					}),
					C.button({
						Name = "Buy5",
						Size = UDim2.new(0.38, -4, 1, 0),
						Position = UDim2.new(0.62, 4, 0, 0),
						Text = "x5",
						MaxTextSize = 22,
						Disabled = Computed(function()
							return short5:get() > 0
						end),
						OnClick = function()
							Remotes.get("BuyEgg"):FireServer(tierId, 5)
						end,
					}),
				},
			}),
			-- Odds toggle and overlay.
			C.button({
				Name = "Odds",
				Size = UDim2.fromOffset(40, 36),
				Position = UDim2.new(1, -6, 0, 6),
				AnchorPoint = Vector2.new(1, 0),
				Color = Theme.colors.purple,
				Text = "%",
				MaxTextSize = 20,
				OnClick = function()
					showOdds:set(not showOdds:get(false))
				end,
			}),
			New("Frame")({
				Name = "OddsOverlay",
				Visible = showOdds,
				Active = true,
				BackgroundColor3 = Theme.colors.slate,
				BackgroundTransparency = 0.04,
				Position = UDim2.fromOffset(6, 46),
				Size = UDim2.new(1, -12, 1, -52),
				ZIndex = 14,
				[Children] = {
					C.padding(10),
					C.label({ Text = "Hatch odds", Size = UDim2.new(1, 0, 0, 22), MaxTextSize = 20, ZIndex = 15 }),
					New("Frame")({
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(0, 28),
						Size = UDim2.new(1, 0, 1, -28),
						ZIndex = 15,
						[Children] = oddsList(tierId),
					}),
				},
			}),
		},
	})
end

-- Small card for a tier you can't buy yet: padlock, name, what unlocks it.
local function lockedCard(tierId: string, order: number, visible: any)
	local tier = Eggs.tiers[tierId]
	return New("Frame")({
		Name = tierId,
		LayoutOrder = order,
		Visible = visible,
		BackgroundColor3 = Theme.colors.slate,
		BorderSizePixel = 0,
		[Children] = {
			C.stroke(Theme.colors.locked, 3),
			C.padlock({
				Size = UDim2.fromOffset(24, 30),
				Position = UDim2.new(0, 10, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Color = Theme.colors.muted,
				ZIndex = 11,
			}),
			C.label({
				Text = string.upper(tier.name),
				Position = UDim2.fromOffset(42, 8),
				Size = UDim2.new(1, -50, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.muted,
				MaxTextSize = 16,
				ZIndex = 11,
			}),
			C.label({
				Text = "REBIRTH " .. tier.unlockRebirth,
				Position = UDim2.fromOffset(42, 30),
				Size = UDim2.new(1, -50, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.gold,
				StrokeThickness = 0,
				MaxTextSize = 13,
				ZIndex = 11,
			}),
		},
	})
end

-- Unlocked eggs get the big cards on top; locked tiers shrink to a row underneath.
return function()
	local rebirths = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.rebirths else 0
	end)
	local function isUnlocked(tierId: string): boolean
		return Eggs.tiers[tierId].unlockRebirth <= rebirths:get()
	end
	local BIG = Vector2.new(186, 228)
	local SMALL = Vector2.new(186, 56)
	local GAP = 12
	local function count(unlocked: boolean): number
		local n = 0
		for _, tierId in Eggs.order do
			if isUnlocked(tierId) == unlocked then
				n += 1
			end
		end
		return n
	end
	local function grid(
		name: string,
		order: number,
		cell: Vector2,
		unlocked: boolean,
		build: (string, number, any) -> any
	)
		local children: { any } = {
			New("UIGridLayout")({
				CellSize = UDim2.fromOffset(cell.X, cell.Y),
				CellPadding = UDim2.fromOffset(GAP, GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		}
		for i, tierId in Eggs.order do
			table.insert(
				children,
				build(
					tierId,
					i,
					Computed(function()
						return isUnlocked(tierId) == unlocked
					end)
				)
			)
		end
		return New("Frame")({
			Name = name,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Visible = Computed(function()
				return count(unlocked) > 0
			end),
			Size = Computed(function()
				local rows = math.ceil(count(unlocked) / 3)
				return UDim2.new(1, 0, 0, rows * cell.Y + math.max(rows - 1, 0) * GAP)
			end),
			[Children] = children,
		})
	end
	local cards: { any } = {
		New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
		C.padding(4), -- room for card outlines inside the scroll clip
		grid("Available", 1, BIG, true, eggCard),
		C.label({
			LayoutOrder = 2,
			Text = "🔒 REBIRTH TO UNLOCK",
			Size = UDim2.new(1, 0, 0, 20),
			MaxTextSize = 15,
			TextColor3 = Theme.colors.muted,
			Visible = Computed(function()
				return count(false) > 0
			end),
		}),
		grid("Locked", 3, SMALL, false, lockedCard),
	}

	return C.panel({
		Title = "🥚 Egg Shop",
		Accent = Theme.colors.purple,
		Size = UDim2.fromOffset(660, 480),
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
			ZIndex = 10,
			[Children] = cards,
		}),
	})
end
