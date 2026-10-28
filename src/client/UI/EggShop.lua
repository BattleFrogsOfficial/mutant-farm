--!strict
-- Egg Shop: a horizontal carousel, one card per tier (Starter .. Cosmic, no looping). Exactly one
-- card is focused: centered, scaled up, full opacity, with name, egg, price buttons and odds (%).
-- Neighbors are smaller and veiled to 60% and show only the egg and name.
--
-- Card states (same in Cash and Gems mode):
--   buyable        price button + x5; can't afford: grey button and "Earn $X more" / "Need N more
--                  Gems" under the name (x5's shortfall shows while hovering/pressing x5)
--   next locked    the lowest tier not unlocked: full-color egg, a progress bar instead of buttons
--                  ("Lab Egg · $12.4K / $25K earned", or "Toxic Egg · Rebirth 1" with Cash / next
--                  rebirth cost). Can take focus.
--   further locked silhouette, soft stroke, name, unlock condition, tagline. Can never take focus.
-- A tier that unlocks mid-session flashes, plays the Rare jingle and wears a NEW ribbon for the
-- next two shop visits.
--
-- Navigation: drag (snaps to the nearest card), arrow buttons, mouse wheel, left/right keys (Enter
-- buys x1), and desktop-only edge-hover auto-scroll. The decisions are shared/Carousel.lua (tested
-- headlessly); this file animates them. Layout numbers: Config/EggShopUI.lua.
--
-- Title row: "Egg Shop", the Cash | Gems switch, the Luck Potion button, close. The switch and the
-- potion aren't rendered where PolicyService restricts paid random items (the server refuses both).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local UI = require(Shared.Config.EggShopUI)
local Products = require(Shared.Config.Products)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Costs = require(Shared.Costs)
local ShopRules = require(Shared.ShopRules)
local Carousel = require(Shared.Carousel)
local MutantModel = require(Shared.MutantModel)
local State = require(script.Parent.Parent.State)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, Value, Observer, OnEvent, Ref =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value, Fusion.Observer, Fusion.OnEvent, Fusion.Ref

local N = #Eggs.order
local PINK = Theme.colors.spend
local W, H = UI.cardWidth, UI.cardHeight

---------------------------------------------------------------------------- state from the snapshot

-- Plain helpers that read State.snapshot directly; every Computed below reads what it needs at
-- its top, unconditionally (the Fusion 0.2 late-dependency gotcha in CLAUDE.md).
local function earnedOf(sn: any): number
	return if sn and sn.stats then sn.stats.totalCashEarned or 0 else 0
end

local function kindOfSnap(sn: any, i: number): string
	if not sn then
		return if i == 1 then "buyable" else "further"
	end
	local base = Eggs.order[i]
	if ShopRules.isUnlocked(base, sn.rebirths, earnedOf(sn)) then
		return "buyable"
	elseif ShopRules.nextLocked(sn.rebirths, earnedOf(sn)) == base then
		return "next"
	end
	return "further"
end

-- Cash or Gems for display: Gems only when the player may buy paid random items.
local mode = Computed(function()
	local sn = State.snapshot:get()
	local wanted = State.shopMode:get()
	return if wanted == "Gems" and sn ~= nil and sn.paidRandomRestricted == false then "Gems" else "Cash"
end)
local gemsAllowed = Computed(function()
	local sn = State.snapshot:get()
	return sn ~= nil and sn.paidRandomRestricted == false
end)
-- Per card: "buyable" | "next" | "further". Computeds only notify when the value changes.
local kinds = {}
for i = 1, N do
	kinds[i] = Computed(function()
		return kindOfSnap(State.snapshot:get(), i)
	end)
end

local function eggIdOf(i: number, m: string): string
	local base = Eggs.order[i]
	return if m == "Gems" then base .. "Gem" else base
end

local function focusable(i: number): boolean
	return kindOfSnap(State.snapshot:get(false), i) ~= "further"
end

---------------------------------------------------------------------------- carousel motion

local anim = { from = 0, to = 0, t0 = -1 }
local morphAt = Value(-10) -- clock time of the last Cash/Gems flip (cards morph in place)

local function goTo(i: number, instant: boolean?)
	State.shopFocus:set(i)
	local target = Carousel.offsetOf(i, UI.pitch)
	if instant then
		State.shopOffset:set(target)
		anim.t0 = -1
	else
		anim.from, anim.to, anim.t0 = State.shopOffset:get(false), target, os.clock()
	end
end

local function step(dir: number)
	goTo(Carousel.step(State.shopFocus:get(false), dir, N, focusable))
end

-- On open: the best egg the player can afford right now (in the current mode), else Starter.
local function bestFocus(): number
	local sn = State.snapshot:get(false)
	if not sn then
		return 1
	end
	local m = mode:get(false)
	for i = N, 1, -1 do
		if kindOfSnap(sn, i) == "buyable" then
			local currency, amount = ShopRules.price(eggIdOf(i, m), 1)
			if (if currency == "Gems" then sn.gems else sn.cash) >= amount then
				return i
			end
		end
	end
	return 1
end

---------------------------------------------------------------------------- NEW ribbons

-- base tier -> shop visits left with the ribbon; base tier -> clock time its flash starts.
local ribbons = Value({} :: { [string]: number })
local flashes = Value({} :: { [string]: number })

local function shopOpen(): boolean
	return State.panel:get(false) == "shop"
end

do
	local last: { rebirths: number, totalCashEarned: number }? = nil
	Observer(State.snapshot):onChange(function()
		local sn = State.snapshot:get(false)
		if not sn then
			return
		end
		local now = { rebirths = sn.rebirths, totalCashEarned = earnedOf(sn) }
		if last then
			local unlocked = ShopRules.newlyUnlocked(last, now)
			if #unlocked > 0 then
				local r, f = table.clone(ribbons:get(false)), table.clone(flashes:get(false))
				for _, base in unlocked do
					-- Unlocked during a visit: that visit doesn't count toward the two.
					r[base] = UI.newRibbonVisits + (if shopOpen() then 1 else 0)
					if shopOpen() then
						f[base] = State.clock:get(false)
					end
				end
				ribbons:set(r)
				flashes:set(f)
				Sfx.play("hatchRare", 0.7)
			end
		end
		last = now
	end)

	local lastPanel = "none"
	Observer(State.panel):onChange(function()
		local panel = State.panel:get(false)
		if panel == "shop" and lastPanel ~= "shop" then
			goTo(bestFocus(), true)
			-- First visit after an unlock that happened while the shop was closed: flash now.
			local f = table.clone(flashes:get(false))
			for base, left in ribbons:get(false) do
				if left == UI.newRibbonVisits and not f[base] then
					f[base] = State.clock:get(false)
				end
			end
			flashes:set(f)
		elseif lastPanel == "shop" and panel == "none" then
			-- A visit ends when the shop closes (not when a Gem tap hops over to the Gem shop).
			local r = {}
			for base, left in ribbons:get(false) do
				if left > 1 then
					r[base] = left - 1
				end
			end
			ribbons:set(r)
		end
		lastPanel = panel
	end)
end

---------------------------------------------------------------------------- pieces

local function oddsList(eggId: string)
	local rows: { any } = {
		New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
	}
	for r, rarity in Rarities.order do
		table.insert(
			rows,
			New("Frame")({
				LayoutOrder = r,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 17),
				ZIndex = 21,
				[Children] = {
					C.label({
						Text = rarity,
						Size = UDim2.new(0.6, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Color3.fromHex(Rarities.info[rarity].color),
						MaxTextSize = 14,
						ZIndex = 21,
					}),
					C.label({
						Text = Format.percent(Eggs.tiers[eggId].odds[rarity]),
						Position = UDim2.fromScale(0.6, 0),
						Size = UDim2.new(0.4, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Right,
						MaxTextSize = 14,
						ZIndex = 21,
					}),
				},
			})
		)
	end
	return rows
end

-- What unlocks a locked tier, short: "$25K earned" / "Rebirth 3".
local function conditionText(base: string): string
	local tier = Eggs.tiers[base]
	if tier.unlockEarned and tier.unlockRebirth == 0 then
		return Format.cash(tier.unlockEarned) .. " EARNED"
	end
	return "REBIRTH " .. tier.unlockRebirth
end

-- Next-locked progress: 0..1 and the label. Only a tier one rebirth away fills from Cash.
local function progressOf(sn: any, base: string): (number, string)
	local tier = Eggs.tiers[base]
	if not sn then
		return 0, tier.name
	end
	if tier.unlockEarned and sn.rebirths == tier.unlockRebirth then
		local earned = earnedOf(sn)
		return math.clamp(earned / tier.unlockEarned, 0, 1),
			string.format("%s · %s / %s earned", tier.name, Format.cash(earned), Format.cash(tier.unlockEarned))
	end
	local away = tier.unlockRebirth - sn.rebirths
	if away > 1 then
		return 0, string.format("%s · %d rebirths to go", tier.name, away)
	end
	local cost = sn.rebirthCost or Costs.rebirth(sn.rebirths)
	return math.clamp(sn.cash / cost, 0, 1), string.format("%s · Rebirth %d", tier.name, tier.unlockRebirth)
end

local function card(i: number)
	local base = Eggs.order[i]
	local kind = kinds[i]
	local showOdds = Value(false)
	local x5Hover = Value(false)
	local pulseAt = Value(-10)

	local function short(sn: any, m: string, quantity: number): number
		if not sn then
			return math.huge
		end
		local currency, amount = ShopRules.price(eggIdOf(i, m), quantity)
		return math.max(0, amount - (if currency == "Gems" then sn.gems else sn.cash))
	end
	local function priceText(m: string, quantity: number): string
		local currency, amount = ShopRules.price(eggIdOf(i, m), quantity)
		return if currency == "Gems" then Format.number(amount) .. " 💎" else Format.cash(amount)
	end
	local function buy(quantity: number)
		local m = mode:get(false)
		if kind:get(false) ~= "buyable" then
			return
		end
		if m == "Gems" and short(State.snapshot:get(false), m, quantity) > 0 then
			-- Short on Gems: straight to the Gem packs, no error.
			State.panel:set("store")
			return
		end
		Remotes.get("BuyEgg"):FireServer(eggIdOf(i, m), quantity)
		pulseAt:set(State.clock:get(false))
	end

	local focused = Computed(function()
		return State.shopFocus:get() == i
	end)
	local function whenFocused(k: string)
		return Computed(function()
			return focused:get() and kind:get() == k
		end)
	end

	-- A price button that pulses once after a buy.
	local function priceButton(quantity: number, size: UDim2, position: UDim2)
		return New("Frame")({
			Name = if quantity == 1 then "Buy1" else "Buy5",
			BackgroundTransparency = 1,
			Size = size,
			Position = position,
			ZIndex = 12,
			[Children] = {
				New("UIScale")({
					Scale = Computed(function()
						local t = State.clock:get() - pulseAt:get()
						return if t >= 0 and t < 0.3 then 1 + 0.12 * math.sin(math.pi * t / 0.3) else 1
					end),
				}),
				C.button({
					Size = UDim2.fromScale(1, 1),
					Text = Computed(function()
						return if quantity == 1 then priceText(mode:get(), 1) else "x5"
					end),
					-- Gems: pink, and short on Gems opens the Gem shop. Cash: green, grey when short.
					Color = Computed(function()
						return if mode:get() == "Gems" then PINK else Theme.colors.toxic
					end),
					Disabled = Computed(function()
						local m, sn = mode:get(), State.snapshot:get()
						return m == "Cash" and short(sn, m, quantity) > 0
					end),
					MaxTextSize = 20,
					ZIndex = 12,
					OnHover = if quantity == 5
						then function(on: boolean)
							x5Hover:set(on)
						end
						else nil,
					OnClick = function()
						buy(quantity)
					end,
				}),
			},
		})
	end

	return New("Frame")({
		Name = base,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		Position = Computed(function()
			return UDim2.new(0.5, Carousel.offsetOf(i, UI.pitch) - State.shopOffset:get(), 0.5, 0)
		end),
		BackgroundColor3 = Computed(function()
			return if kind:get() == "further" then Theme.colors.panel else Theme.colors.slateLight
		end),
		BorderSizePixel = 0,
		ZIndex = Computed(function()
			return if focused:get() then 11 else 10
		end),
		[Children] = {
			New("UIScale")({
				Scale = Computed(function()
					local s = if focused:get() then UI.focusScale else 1
					local t = State.clock:get() - morphAt:get()
					if t >= 0 and t < UI.morphSeconds then
						s *= 1 - UI.morphDip * math.sin(math.pi * t / UI.morphSeconds)
					end
					return s
				end),
			}),
			New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				LineJoinMode = Enum.LineJoinMode.Miter,
				Thickness = Computed(function()
					return if kind:get() == "further" then 2 else 3
				end),
				Transparency = Computed(function()
					return if kind:get() == "further" then 0.5 else 0
				end),
				Color = Computed(function()
					local k, m = kind:get(), mode:get()
					if k == "further" then
						return Theme.colors.muted
					end
					return if m == "Gems" then PINK else Color3.fromHex(Eggs.tiers[base].color)
				end),
			}),
			-- Egg art: the variant for the current mode; a desaturated silhouette when further locked.
			-- Rebuilt only when the mode or the card state changes.
			Computed(function()
				local m, k = mode:get(), kind:get()
				return Viewport.new({
					Build = function()
						return MutantModel.buildEgg(eggIdOf(i, m), 1, {})
					end,
					Spin = k ~= "further",
					Silhouette = k == "further",
					Size = UDim2.fromOffset(78, 76),
					Position = UDim2.new(0.5, 0, 0, 24),
					AnchorPoint = Vector2.new(0.5, 0),
					ZIndex = 11,
				})
			end, Fusion.cleanup),
			C.label({
				Name = "Title",
				Text = Computed(function()
					return Eggs.tiers[eggIdOf(i, mode:get())].name
				end),
				Position = UDim2.fromOffset(6, 102),
				Size = UDim2.new(1, -12, 0, 22),
				MaxTextSize = 20,
				TextColor3 = Computed(function()
					return if kind:get() == "further" then Theme.colors.muted else Theme.colors.white
				end),
				ZIndex = 12,
			}),
			-- Under the name: the shortfall / grow info (focused buyable), or the unlock condition.
			C.label({
				Name = "Line",
				Position = UDim2.fromOffset(6, 125),
				Size = UDim2.new(1, -12, 0, 14),
				MaxTextSize = 12,
				StrokeThickness = 1.5,
				ZIndex = 12,
				Visible = Computed(function()
					local k, f = kind:get(), focused:get()
					return k == "further" or (k == "buyable" and f)
				end),
				TextColor3 = Computed(function()
					local k, m, sn, hover = kind:get(), mode:get(), State.snapshot:get(), x5Hover:get()
					if k == "further" then
						return Theme.colors.gold
					end
					local s = if hover then short(sn, m, 5) else short(sn, m, 1)
					return if s > 0 then Theme.colors.gold else Theme.colors.cream
				end),
				Text = Computed(function()
					local k, m, sn, hover = kind:get(), mode:get(), State.snapshot:get(), x5Hover:get()
					if k == "further" then
						return "🔒 " .. conditionText(base)
					end
					local quantity = if hover and short(sn, m, 5) > 0 then 5 else 1
					local s = short(sn, m, quantity)
					local suffix = if quantity == 5 then " for x5" else ""
					if s > 0 then
						return if m == "Gems"
							then "Need " .. Format.number(s) .. " more Gems" .. suffix
							else "Earn " .. Format.cash(s) .. " more" .. suffix
					end
					local tier = Eggs.tiers[base]
					return string.format(
						"Grows %s · sells %s+",
						Format.duration(tier.growTime),
						Format.cash(tier.baseValue)
					)
				end),
			}),
			-- Further locked: the tagline.
			C.label({
				Name = "Tagline",
				Text = Eggs.tiers[base].tagline,
				Position = UDim2.fromOffset(8, 144),
				Size = UDim2.new(1, -16, 0, 44),
				TextWrapped = true,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 13,
				Visible = Computed(function()
					return kind:get() == "further"
				end),
				ZIndex = 12,
			}),
			-- Focused + buyable: price and x5.
			New("Frame")({
				Name = "BuyRow",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(6, 146),
				Size = UDim2.new(1, -12, 0, 46),
				Visible = whenFocused("buyable"),
				ZIndex = 12,
				[Children] = {
					priceButton(1, UDim2.new(0.62, -3, 1, 0), UDim2.new()),
					priceButton(5, UDim2.new(0.38, -3, 1, 0), UDim2.new(0.62, 3, 0, 0)),
				},
			}),
			-- Focused + next locked: the progress card.
			New("Frame")({
				Name = "Progress",
				Position = UDim2.fromOffset(6, 140),
				Size = UDim2.new(1, -12, 0, 52),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				Visible = whenFocused("next"),
				ZIndex = 12,
				[Children] = {
					New("Frame")({
						Name = "Fill",
						BorderSizePixel = 0,
						BackgroundColor3 = Computed(function()
							return if mode:get() == "Gems" then PINK else Theme.colors.toxicDark
						end),
						Size = Computed(function()
							local fill = progressOf(State.snapshot:get(), base)
							return UDim2.fromScale(fill, 1)
						end),
						ZIndex = 13,
					}),
					C.label({
						Name = "Text",
						Position = UDim2.fromOffset(5, 4),
						Size = UDim2.new(1, -10, 1, -8),
						TextWrapped = true,
						MaxTextSize = 15,
						StrokeThickness = 2,
						ZIndex = 14,
						Text = Computed(function()
							local _, text = progressOf(State.snapshot:get(), base)
							return text
						end),
					}),
				},
			}),
			-- Gem mode: "2x RARITY ODDS" on every unlocked card.
			New("Frame")({
				Name = "GemBadge",
				Position = UDim2.fromOffset(5, 5),
				Size = UDim2.fromOffset(92, 16),
				BackgroundColor3 = PINK,
				BorderSizePixel = 0,
				Visible = Computed(function()
					return mode:get() == "Gems" and kind:get() == "buyable"
				end),
				ZIndex = 13,
				[Children] = C.label({
					Text = "2x RARITY ODDS",
					Size = UDim2.new(1, -6, 1, -4),
					Position = UDim2.fromOffset(3, 2),
					MaxTextSize = 11,
					StrokeThickness = 1.5,
					ZIndex = 14,
				}),
			}),
			-- Odds for the variant on display (focused, not further locked).
			C.button({
				Name = "Odds",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(30, 26),
				Color = Theme.colors.navy,
				Text = "%",
				MaxTextSize = 14,
				ZIndex = 15,
				Visible = Computed(function()
					return focused:get() and kind:get() ~= "further"
				end),
				OnClick = function()
					showOdds:set(not showOdds:get(false))
				end,
			}),
			New("Frame")({
				Name = "OddsOverlay",
				Visible = Computed(function()
					return showOdds:get() and focused:get()
				end),
				Active = true,
				BackgroundColor3 = Theme.colors.slate,
				BackgroundTransparency = 0.03,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(4, 34),
				Size = UDim2.new(1, -8, 1, -38),
				ZIndex = 20,
				[Children] = {
					C.padding(7),
					C.label({
						Text = Computed(function()
							return if mode:get() == "Gems" then "GEM ODDS" else "HATCH ODDS"
						end),
						Size = UDim2.new(1, 0, 0, 18),
						MaxTextSize = 14,
						ZIndex = 21,
					}),
					Computed(function()
						local m = mode:get()
						return New("Frame")({
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(0, 22),
							Size = UDim2.new(1, 0, 1, -22),
							ZIndex = 21,
							[Children] = oddsList(eggIdOf(i, m)),
						})
					end, Fusion.cleanup),
				},
			}),
			-- Unlocked this session: NEW ribbon and a short flash.
			New("Frame")({
				Name = "New",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(-8, 30),
				Size = UDim2.fromOffset(52, 22),
				Rotation = -10,
				BackgroundColor3 = Theme.colors.toxic,
				BorderSizePixel = 0,
				Visible = Computed(function()
					local visits, k = ribbons:get()[base] or 0, kind:get()
					return visits > 0 and k == "buyable"
				end),
				ZIndex = 17,
				[Children] = {
					C.stroke(Theme.colors.ink, 2.5),
					C.label({
						Text = "NEW",
						Size = UDim2.new(1, -8, 1, -6),
						Position = UDim2.fromOffset(4, 3),
						MaxTextSize = 15,
						ZIndex = 18,
					}),
				},
			}),
			New("Frame")({
				Name = "Flash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				BackgroundTransparency = Computed(function()
					local start = flashes:get()[base]
					local t = if start then State.clock:get() - start else math.huge
					return if t >= 0 and t < UI.flashSeconds then 0.2 + 0.8 * (t / UI.flashSeconds) else 1
				end),
				ZIndex = 16,
			}),
			-- Neighbors: a panel-colored veil so they read at ~60% opacity.
			New("Frame")({
				Name = "Veil",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.colors.panel,
				BackgroundTransparency = UI.neighborOpacity,
				BorderSizePixel = 0,
				Visible = Computed(function()
					return not focused:get()
				end),
				ZIndex = 19,
			}),
		},
	})
end

-- Cash | Gems switch for the title row (not rendered where paid random items are restricted).
local function modeSwitch()
	local function segment(name: string, label: string, x: number)
		local on = Computed(function()
			return mode:get() == name
		end)
		return New("TextButton")({
			Name = name,
			Text = "",
			AutoButtonColor = false,
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(0.5, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = Computed(function()
				return if on:get() then Theme.colors.navy else Theme.colors.ink
			end),
			ZIndex = 4,
			[OnEvent("Activated")] = function()
				if State.shopMode:get(false) ~= name then
					State.shopMode:set(name) -- session only; the strip doesn't move
					morphAt:set(State.clock:get(false))
					Sfx.play("click", 0.5)
				end
			end,
			[Children] = {
				C.label({
					Text = label,
					Size = UDim2.new(1, -8, 1, -8),
					Position = UDim2.fromOffset(4, 4),
					MaxTextSize = 15,
					TextColor3 = Computed(function()
						return if on:get() then Theme.colors.white else Theme.colors.muted
					end),
					ZIndex = 5,
				}),
				New("Frame")({
					Name = "Underline",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					Size = UDim2.new(1, 0, 0, 3),
					BorderSizePixel = 0,
					BackgroundColor3 = if name == "Gems" then PINK else Theme.colors.gold,
					Visible = on,
					ZIndex = 5,
				}),
			},
		})
	end
	return New("Frame")({
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -220, 0.5, -2),
		Size = UDim2.fromOffset(170, 36),
		BackgroundColor3 = Theme.colors.ink,
		BorderSizePixel = 0,
		Visible = gemsAllowed,
		ZIndex = 4,
		[Children] = {
			C.stroke(Theme.colors.ink, 3),
			segment("Cash", "💰 CASH", 0),
			segment("Gems", "💎 GEMS", 0.5),
		},
	})
end

local function potionButton()
	local potion = Products.gems.LuckPotion
	return C.button({
		Name = "Potion",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, -2),
		Size = UDim2.fromOffset(150, 40),
		Color = PINK,
		Text = string.format("🍀 LUCK · %d 💎", potion.cost),
		MaxTextSize = 15,
		ZIndex = 4,
		Visible = gemsAllowed,
		OnClick = function()
			if State.gems:get(false) < potion.cost then
				State.panel:set("store")
				return
			end
			Remotes.get("BuyPotion"):FireServer()
		end,
	})
end

---------------------------------------------------------------------------- input

local function wireInput(stripRef: any, panelRef: any)
	local dragging: { startX: number, startOffset: number, lastX: number, dir: number }? = nil
	local autoTimer, autoDir = 0, 0

	local function pixelsToDesign(px: number): number
		local s = State.screen:get(false).scale
		return px / math.max(s, 0.01)
	end

	-- Drag: the strip follows the pointer; on release it settles on the nearest focusable card.
	local function release()
		local d = dragging
		if not d then
			return
		end
		dragging = nil
		local i = Carousel.settle(State.shopOffset:get(false), UI.pitch, N, focusable, d.dir)
		goTo(i)
	end

	UserInputService.InputChanged:Connect(function(input)
		local d = dragging
		if
			d
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local x = input.Position.X
			if x ~= d.lastX then
				d.dir = if x < d.lastX then 1 else -1 -- pulling left moves toward later tiers
				d.lastX = x
			end
			local offset = d.startOffset - pixelsToDesign(x - d.startX)
			State.shopOffset:set(Carousel.clampDrag(offset, UI.pitch, N, UI.dragOvershoot))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			release()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not shopOpen() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left then
			step(-1)
		elseif input.KeyCode == Enum.KeyCode.Right then
			step(1)
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			local i = State.shopFocus:get(false)
			if kindOfSnap(State.snapshot:get(false), i) == "buyable" then
				local m = mode:get(false)
				local sn = State.snapshot:get(false)
				local currency, amount = ShopRules.price(eggIdOf(i, m), 1)
				if m == "Gems" and sn and sn.gems < amount then
					State.panel:set("store")
				elseif currency == "Cash" and sn and sn.cash < amount then
					Sfx.play("error", 0.4)
				else
					Remotes.get("BuyEgg"):FireServer(eggIdOf(i, m), 1)
				end
			end
		end
	end)

	local stripApi = {
		begin = function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				anim.t0 = -1
				dragging = {
					startX = input.Position.X,
					startOffset = State.shopOffset:get(false),
					lastX = input.Position.X,
					dir = 0,
				}
			end
		end,
		changed = function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				goTo(Carousel.wheel(State.shopFocus:get(false), input.Position.Z, N, focusable))
			end
		end,
	}

	-- Snap tween and desktop edge-hover auto-scroll.
	RunService.RenderStepped:Connect(function(dt)
		if anim.t0 >= 0 then
			local k = math.clamp((os.clock() - anim.t0) / UI.snapSeconds, 0, 1)
			local e = k * k * (3 - 2 * k)
			State.shopOffset:set(anim.from + (anim.to - anim.from) * e)
			if k >= 1 then
				anim.t0 = -1
			end
		end
		local panel = panelRef:get(false) :: GuiObject?
		if not shopOpen() or dragging or not panel then
			autoTimer, autoDir = 0, 0
			return
		end
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local pos, size = panel.AbsolutePosition, panel.AbsoluteSize
		local inside = mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
		local fraction = if size.X > 0 then (mouse.X - pos.X) / size.X else 0.5
		local dir, every =
			Carousel.autoScroll(UI, fraction, inside, UserInputService.MouseEnabled, UserInputService.TouchEnabled)
		if dir == 0 or not every then
			autoTimer, autoDir = 0, 0 -- stops the moment the mouse leaves the zone
			return
		end
		if dir ~= autoDir then
			autoTimer, autoDir = 0, dir
		end
		autoTimer += dt
		if autoTimer >= every then
			autoTimer = 0
			step(dir)
		end
	end)
	return stripApi
end

---------------------------------------------------------------------------- panel

return function()
	local stripRef = Value(nil)
	local panelRef = Value(nil)
	-- Input wiring needs a live client (the UI preview builds this headlessly without one).
	local api: any = nil
	pcall(function()
		api = wireInput(stripRef, panelRef)
	end)

	local cards: { any } = {}
	for i = 1, N do
		table.insert(cards, card(i))
	end
	local stripWidth = UI.panelWidth - 32 - 2 * (UI.arrowSize + 8)
	local stripHeight = math.ceil(H * UI.focusScale) + 14

	local function arrow(dir: number)
		return C.button({
			Name = if dir < 0 then "ArrowLeft" else "ArrowRight",
			AnchorPoint = Vector2.new(if dir < 0 then 0 else 1, 0.5),
			Position = UDim2.new(if dir < 0 then 0 else 1, 0, 0, stripHeight / 2),
			Size = UDim2.fromOffset(UI.arrowSize, UI.arrowSize),
			Color = Theme.colors.navy,
			Text = if dir < 0 then "<" else ">",
			MaxTextSize = 34,
			ZIndex = 12,
			-- Hidden at an end (nothing focusable further that way).
			Visible = Computed(function()
				local f, sn = State.shopFocus:get(), State.snapshot:get()
				local _ = sn
				return Carousel.step(f, dir, N, focusable) ~= f
			end),
			OnClick = function()
				step(dir)
			end,
		})
	end

	local dots: { any } = {
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i = 1, N do
		table.insert(
			dots,
			New("Frame")({
				Name = "Dot" .. i,
				LayoutOrder = i,
				BorderSizePixel = 0,
				Size = Computed(function()
					return if State.shopFocus:get() == i then UDim2.fromOffset(16, 16) else UDim2.fromOffset(11, 11)
				end),
				BackgroundColor3 = Computed(function()
					local k = kinds[i]:get()
					if State.shopFocus:get() == i then
						return Theme.colors.gold
					end
					return if k == "buyable" then Theme.colors.cream else Theme.colors.ink
				end),
				[Children] = C.stroke(Theme.colors.muted, 1.5),
			})
		)
	end

	return C.panel({
		Title = "🥚 Egg Shop",
		TitleWidth = 230,
		Accent = Theme.colors.purple,
		Size = UDim2.fromOffset(UI.panelWidth, UI.panelHeight),
		IsOpen = Computed(function()
			return State.panel:get() == "shop"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Header = { modeSwitch(), potionButton() },
		Content = New("Frame")({
			Name = "Carousel",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 10,
			[Ref] = panelRef,
			[Children] = {
				arrow(-1),
				arrow(1),
				New("TextButton")({
					Name = "Strip",
					Text = "",
					AutoButtonColor = false,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.fromOffset(stripWidth, stripHeight),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					ZIndex = 10,
					[Ref] = stripRef,
					[OnEvent("InputBegan")] = function(input)
						if api then
							api.begin(input)
						end
					end,
					[OnEvent("InputChanged")] = function(input)
						if api then
							api.changed(input)
						end
					end,
					[Children] = cards,
				}),
				New("Frame")({
					Name = "Dots",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, stripHeight + 10),
					Size = UDim2.fromOffset(N * 26, 18),
					BackgroundTransparency = 1,
					ZIndex = 10,
					[Children] = dots,
				}),
			},
		}),
	})
end
