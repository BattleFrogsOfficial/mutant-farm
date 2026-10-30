--!strict
-- Upgrades, in the shop's chrome (C.panel: frame, title bar, close X). Two sections, a row per
-- upgrade: glyph, name, a one-line effect, level pips, and a price button on the right like the
-- Egg Shop's ("$2K" navy for Cash, "150 [gem]" pink for Gems, grey "MAX" when there's nothing left
-- to buy).
--   CASH UPGRADES  Growth Speed, Mutation Odds: 5 levels, +10% each; reset on rebirth, prices
--                  scale with rebirths (shared/Costs.lua, the server charges the same).
--   GEM UPGRADES   Pen Slots, Permanent Luck, Offline Mutations (shared/GemUpgrades.lua): kept
--                  through rebirth. The server decides (BuyGemUpgrade); this only previews.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Config.Upgrades)
local GemUpgrades = require(Shared.GemUpgrades)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local ROW_H = 52
local BUTTON_W = 124

type Row = {
	icon: string,
	name: string,
	effect: () -> string, -- read inside a Computed
	level: () -> number,
	levels: () -> number?, -- pips; nil = no pips (Pen Slots: one level per rebirth)
	cost: () -> number?, -- nil = MAX
	gems: boolean,
	buy: () -> (),
}

local function snap(): any
	return State.snapshot:get()
end

local function pct(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

local function row(order: number, r: Row)
	local pips: { any } = {
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
	}
	for i = 1, 5 do
		table.insert(
			pips,
			New("Frame")({
				Name = "Pip",
				LayoutOrder = i,
				Size = UDim2.fromOffset(18, 12),
				BorderSizePixel = 0,
				Visible = Computed(function()
					local n = r.levels()
					return n ~= nil and i <= n
				end),
				BackgroundColor3 = Computed(function()
					return if r.level() >= i then Theme.colors.toxic else Theme.colors.slateLight
				end),
				ZIndex = 4,
				[Children] = C.stroke(Theme.colors.ink, 2),
			})
		)
	end
	return New("Frame")({
		Name = "Row",
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, ROW_H),
		BackgroundColor3 = Theme.colors.panelHi,
		BorderSizePixel = 0,
		ZIndex = 3,
		[Children] = {
			C.stroke(Theme.colors.ink, 3),
			C.icon(r.icon, 34, nil, { Position = UDim2.fromOffset(10, 8), ZIndex = 4 }),
			C.label({
				Name = "Name",
				Text = r.name,
				Position = UDim2.fromOffset(56, 5),
				Size = UDim2.new(1, -(56 + BUTTON_W + 128), 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				ZIndex = 4,
			}),
			C.label({
				Name = "Effect",
				Text = Computed(r.effect),
				Position = UDim2.fromOffset(56, 28),
				Size = UDim2.new(1, -(56 + BUTTON_W + 128), 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 14,
				ZIndex = 4,
			}),
			New("Frame")({
				Name = "Pips",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(BUTTON_W + 22), 0.5, 0),
				Size = UDim2.fromOffset(110, 16),
				BackgroundTransparency = 1,
				ZIndex = 4,
				[Children] = pips,
			}),
			C.button({
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, -2),
				Size = UDim2.fromOffset(BUTTON_W, 40),
				Color = Computed(function()
					if r.cost() == nil then
						return Theme.colors.locked
					end
					return if r.gems then Theme.colors.spend else Theme.colors.navy
				end),
				Disabled = Computed(function()
					local c = r.cost()
					return c == nil or (not r.gems and State.cash:get() < c)
				end),
				Text = Computed(function()
					local c = r.cost()
					if c == nil then
						return "MAX"
					end
					return if r.gems then Format.number(c) else Format.cash(c)
				end),
				IconAfter = if r.gems
					then Computed(function()
						return if r.cost() ~= nil then "gem" else nil
					end)
					else nil,
				IconSize = 20,
				MaxTextSize = 20,
				ZIndex = 5,
				OnClick = r.buy,
			}),
		},
	})
end

local function cashRow(order: number, kind: string, icon: string, name: string, what: string)
	local cfg = (Upgrades :: any)[kind]
	local function level(): number
		local s = snap()
		return if s and s.upgrades then s.upgrades[kind] or 0 else 0
	end
	return row(order, {
		icon = icon,
		name = name,
		effect = function()
			return string.format("%s · now +%s", what, pct(level() * cfg.bonusPerLevel))
		end,
		level = level,
		levels = function()
			return cfg.levels
		end,
		cost = function()
			local s = snap()
			return if s and s.upgradeCosts then s.upgradeCosts[kind] else nil
		end,
		gems = false,
		buy = function()
			Remotes.get("BuyUpgrade"):FireServer(kind)
		end,
	})
end

local function gemRow(order: number, kind: string, icon: string, name: string, effect: (number, any) -> string)
	local function level(): number
		local s = snap()
		return GemUpgrades.level(if s then s.gemUpgrades else nil, kind)
	end
	local function cost(): number?
		local s = snap()
		if not s then
			return nil
		end
		local ownsPass = s.ownedPasses ~= nil and s.ownedPasses.OfflineMutations == true
		return GemUpgrades.cost(kind, level(), s.rebirths, ownsPass)
	end
	return row(order, {
		icon = icon,
		name = name,
		effect = function()
			return effect(level(), snap())
		end,
		level = level,
		levels = function()
			if kind == "penSlots" then
				return nil
			end
			local s = snap()
			if kind == "offline" and s and s.ownedPasses and s.ownedPasses.OfflineMutations then
				return nil
			end
			return GemUpgrades.levels(kind, 0)
		end,
		cost = cost,
		gems = true,
		buy = function()
			local c = cost()
			if not c then
				return
			end
			if State.gems:get(false) < c then
				State.panel:set("store") -- short on Gems: straight to the packs
				return
			end
			Remotes.get("BuyGemUpgrade"):FireServer(kind)
		end,
	})
end

local function section(order: number, text: string, icon: string)
	return C.iconText({
		LayoutOrder = order,
		Icon = icon,
		IconSize = 20,
		Text = text,
		Align = "Left",
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextColor3 = Theme.colors.cream,
		ZIndex = 3,
	})
end

return function()
	local gem = Upgrades.gem
	return C.panel({
		Title = "Upgrades",
		Icon = "arrowUp",
		Accent = Theme.colors.toxicDark,
		Size = UDim2.fromOffset(640, 440),
		IsOpen = Computed(function()
			return State.panel:get() == "upgrades"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = New("Frame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
			[Children] = {
				New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
				New("UIPadding")({ PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4) }),
				section(1, "CASH UPGRADES", "coin"),
				cashRow(2, "growthSpeed", "bolt", "GROWTH SPEED", "Eggs grow 10% faster"),
				cashRow(3, "mutationOdds", "sparkle", "MUTATION ODDS", "10% more mutations"),
				section(4, "GEM UPGRADES", "gem"),
				gemRow(5, "penSlots", "paw", "PEN SLOTS", function(level)
					return string.format(
						"+%d pen mutants a rebirth · now %d",
						gem.penSlots.slotsPerLevel,
						GemUpgrades.penCapacity(level)
					)
				end),
				gemRow(6, "luck", "clover", "PERMANENT LUCK", function(level)
					return string.format(
						"+%s luck forever · now +%s",
						pct(gem.luck.bonusPerLevel),
						pct(GemUpgrades.luckBonus(level))
					)
				end),
				gemRow(7, "offline", "moon", "OFFLINE MUTATIONS", function(level, s)
					if s and s.ownedPasses and s.ownedPasses.OfflineMutations then
						return "Your pass covers all time away"
					end
					return string.format(
						"+%d h offline rolls · now %d h",
						gem.offline.secondsPerLevel // 3600,
						GemUpgrades.offlineCap(level) // 3600
					)
				end),
				C.label({
					LayoutOrder = 8,
					Text = "Cash upgrades reset when you rebirth. Gem upgrades stay.",
					Size = UDim2.new(1, 0, 0, 18),
					TextColor3 = Theme.colors.muted,
					StrokeThickness = 0,
					MaxTextSize = 14,
					ZIndex = 3,
				}),
			},
		}),
	})
end
