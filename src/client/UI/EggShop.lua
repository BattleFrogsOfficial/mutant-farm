--!strict
-- Egg Shop: a horizontal carousel, one card per tier (Starter .. Cosmic, no looping). The card at
-- the center is focused: full size, full opacity, with name, egg, price buttons and odds (%).
-- Cards shrink and fade continuously with their distance from the center (sideScale and the
-- neighbor veil one pitch away), so the strip glides instead of jumping between fixed states.
-- Neighbors show only the egg and name (no price, odds or Gem badge).
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
-- Navigation: drag (with a little flick), tap a side card, arrow buttons, mouse wheel, Left/Right
-- keys (Enter buys x1), and desktop-only edge-hover auto-scroll. Keys and the wheel are bound with
-- ContextActionService while the shop is open and sunk, so the camera never sees them. The
-- decisions are shared/Carousel.lua (tested headlessly); this file animates them. Layout numbers:
-- Config/EggShopUI.lua.
--
-- Title row: "Egg Shop", the Cash | Gems switch, the Luck Potion button, close. The switch and the
-- potion aren't rendered where PolicyService restricts paid random items (the server refuses both).
--
-- Limited eggs (Config/LimitedEggs.lua) on sale when the shop opens take the left-most slots, in
-- both modes: always priced in Gems (pink), an "ENDS IN 3d 4h" ribbon, no Gem badge. The first
-- time a player opens the shop while one is on sale, the strip opens on it (saved server-side as
-- seenLimited via the SeenLimited intent) with a NEW ribbon like an unlock; after that the usual
-- best-affordable rule. Restricted players never see them. Cards sit in "slots": slot 1.. #shown
-- are the limited eggs, then the base tiers; State.shopFocus is a slot.

local ContextActionService = game:GetService("ContextActionService")
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

local BASE_N = #Eggs.order
local PINK = Theme.colors.spend
local W, H = UI.cardWidth, UI.cardHeight
local STRIP_WIDTH = UI.panelWidth - 32 - 2 * (UI.arrowSize + 8)
local STRIP_HEIGHT = H + 10

---------------------------------------------------------------------------- state from the snapshot

-- Plain helpers that read State.snapshot directly; every Computed below reads what it needs at
-- its top, unconditionally (the Fusion 0.2 late-dependency gotcha in CLAUDE.md).
local function earnedOf(sn: any): number
	return if sn and sn.stats then sn.stats.totalCashEarned or 0 else 0
end

-- Base tier i (1..BASE_N): "buyable" | "next" | "further".
local function tierKind(sn: any, i: number): string
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

-- Limited eggs on show this visit (set when the shop opens, so one ending mid-visit stays until
-- the next open). They fill slots 1..#shown; base tier i is slot #shown + i.
local shownLimited = Value({} :: { string })
local function limitedCount(): number
	return #shownLimited:get(false)
end
local function slotCount(): number
	return limitedCount() + BASE_N
end

-- Slot s: "buyable" for a limited egg, else its base tier's kind.
local function kindOfSnap(sn: any, s: number): string
	local l = limitedCount()
	if s <= l then
		return "buyable"
	end
	return tierKind(sn, s - l)
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
-- Per base tier: "buyable" | "next" | "further". Computeds only notify when the value changes.
local kinds = {}
for i = 1, BASE_N do
	kinds[i] = Computed(function()
		return tierKind(State.snapshot:get(), i)
	end)
end

-- The egg a slot sells in mode m (a limited egg ignores the mode: always its own, for Gems).
local function eggIdOf(s: number, m: string): string
	local l = limitedCount()
	if s <= l then
		return shownLimited:get(false)[s]
	end
	local base = Eggs.order[s - l]
	return if m == "Gems" then base .. "Gem" else base
end

local function focusable(i: number): boolean
	return kindOfSnap(State.snapshot:get(false), i) ~= "further"
end

local function shopOpen(): boolean
	return State.panel:get(false) == "shop"
end

---------------------------------------------------------------------------- carousel motion

-- The strip glides toward `target` every frame (Carousel.approach); input only moves the target,
-- so quick repeated presses retarget smoothly instead of restarting a tween.
local motion = { target = 0, armed = true }
local morphAt = Value(-10) -- clock time of the last Cash/Gems flip (cards morph in place)

local function goTo(i: number, instant: boolean?)
	State.shopFocus:set(i)
	motion.target = Carousel.offsetOf(i, UI.pitch)
	if instant then
		State.shopOffset:set(motion.target)
	end
end

-- One step from where the strip is heading (not from where it currently is mid-glide).
local function step(dir: number)
	goTo(Carousel.step(State.shopFocus:get(false), dir, slotCount(), focusable))
end

local function buyFocused()
	local i = State.shopFocus:get(false)
	local sn = State.snapshot:get(false)
	if not sn or kindOfSnap(sn, i) ~= "buyable" then
		return
	end
	local m = mode:get(false)
	local currency, amount = ShopRules.price(eggIdOf(i, m), 1)
	if currency == "Gems" and sn.gems < amount then
		State.panel:set("store")
	elseif currency == "Cash" and sn.cash < amount then
		Sfx.play("error", 0.4)
	else
		Remotes.get("BuyEgg"):FireServer(eggIdOf(i, m), 1)
	end
end

-- On open: the best base egg the player can afford right now (in the current mode), else Starter.
local function bestFocus(): number
	local sn = State.snapshot:get(false)
	local l = limitedCount()
	if not sn then
		return l + 1
	end
	local m = mode:get(false)
	for i = BASE_N, 1, -1 do
		if tierKind(sn, i) == "buyable" then
			local currency, amount = ShopRules.price(eggIdOf(l + i, m), 1)
			if (if currency == "Gems" then sn.gems else sn.cash) >= amount then
				return l + i
			end
		end
	end
	return l + 1
end

---------------------------------------------------------------------------- NEW ribbons

-- base tier -> shop visits left with the ribbon; base tier -> clock time its flash starts.
local ribbons = Value({} :: { [string]: number })
local flashes = Value({} :: { [string]: number })

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
			-- Limited eggs on sale right now (never for policy-restricted players).
			local sn = State.snapshot:get(false)
			local restricted = sn == nil or sn.paidRandomRestricted ~= false
			local shown = ShopRules.shownLimited(State.now:get(false), restricted)
			shownLimited:set(shown)
			-- First open while one is on sale: open on it, NEW ribbon + flash like an unlock.
			local unseen = nil
			for s, id in shown do
				if not (sn and sn.seenLimited and sn.seenLimited[id]) and not unseen then
					unseen = s
					local r = table.clone(ribbons:get(false))
					r[id] = UI.newRibbonVisits
					ribbons:set(r)
					Sfx.play("hatchRare", 0.7)
					task.spawn(function()
						pcall(function()
							Remotes.get("SeenLimited"):FireServer(id)
						end)
					end)
				end
			end
			goTo(unseen or bestFocus(), true)
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
		New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	}
	for r, rarity in Rarities.order do
		table.insert(
			rows,
			New("Frame")({
				LayoutOrder = r,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				ZIndex = 21,
				[Children] = {
					C.label({
						Text = rarity,
						Size = UDim2.new(0.6, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Color3.fromHex(Rarities.info[rarity].color),
						MaxTextSize = 19,
						ZIndex = 21,
					}),
					C.label({
						Text = Format.percent(Eggs.tiers[eggId].odds[rarity]),
						Position = UDim2.fromScale(0.6, 0),
						Size = UDim2.new(0.4, 0, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Right,
						MaxTextSize = 19,
						ZIndex = 21,
					}),
				},
			})
		)
	end
	return rows
end

local FURTHER_TEXT = UI.furtherText

-- A grow time, short: "5m", "1h", "1h 30m".
local function growShort(seconds: number): string
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if h > 0 then
		return if m > 0 then string.format("%dh %dm", h, m) else h .. "h"
	end
	return m .. "m"
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

-- "ENDS IN 3d 4h" for a limited egg's ribbon.
local function endsIn(endsAt: number, now: number): string
	return "ENDS IN " .. Format.timeLeft(endsAt - now)
end

-- One card. spec: a base tier (i = its index) or a limited egg (limited = its id).
local function card(spec: { i: number?, limited: string? })
	local limited = spec.limited
	local base = limited or Eggs.order[spec.i :: number]
	local tier = Eggs.tiers[base]
	local kind = if limited
		then Computed(function()
			return "buyable"
		end)
		else kinds[spec.i :: number]
	local showOdds = Value(false)
	local x5Hover = Value(false)
	local pulseAt = Value(-10)

	-- This card's slot right now (nil: a limited egg not on show this visit).
	local function slot(): number?
		local shown = shownLimited:get()
		if limited then
			return table.find(shown, limited)
		end
		return #shown + (spec.i :: number)
	end
	-- The egg it sells in mode m.
	local function eggOf(m: string): string
		return if limited then limited elseif m == "Gems" then base .. "Gem" else base
	end
	local function currencyOf(m: string): string
		return (ShopRules.price(eggOf(m), 1))
	end

	-- Signed distance (design px) of this card's center from the strip center.
	local function distance(): number
		return Carousel.offsetOf(slot() or 1, UI.pitch) - State.shopOffset:get()
	end
	-- The card nearest the center shows its details (live, so they follow a drag).
	local near = Computed(function()
		return math.abs(distance()) < UI.pitch / 2
	end)
	local function whenNear(k: string)
		return Computed(function()
			return near:get() and kind:get() == k
		end)
	end

	local function short(sn: any, m: string, quantity: number): number
		if not sn then
			return math.huge
		end
		local currency, amount = ShopRules.price(eggOf(m), quantity)
		return math.max(0, amount - (if currency == "Gems" then sn.gems else sn.cash))
	end
	local function priceText(m: string, quantity: number): string
		local currency, amount = ShopRules.price(eggOf(m), quantity)
		return if currency == "Gems" then Format.number(amount) else Format.cash(amount)
	end
	local function buy(quantity: number)
		local m = mode:get(false)
		if kind:get(false) ~= "buyable" then
			return
		end
		if currencyOf(m) == "Gems" and short(State.snapshot:get(false), m, quantity) > 0 then
			-- Short on Gems: straight to the Gem packs, no error.
			State.panel:set("store")
			return
		end
		Remotes.get("BuyEgg"):FireServer(eggOf(m), quantity)
		pulseAt:set(State.clock:get(false))
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
					-- A Gem price carries the gem glyph after it ("600 [gem]").
					IconAfter = Computed(function()
						return if quantity == 1 and currencyOf(mode:get()) == "Gems" then "gem" else nil
					end),
					IconSize = 24,
					-- Gems: pink, and short on Gems opens the Gem shop. Cash: green, grey when short.
					Color = Computed(function()
						return if currencyOf(mode:get()) == "Gems" then PINK else Theme.colors.toxic
					end),
					Disabled = Computed(function()
						local m, sn = mode:get(), State.snapshot:get()
						return currencyOf(m) == "Cash" and short(sn, m, quantity) > 0
					end),
					MaxTextSize = 24,
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
		Visible = Computed(function()
			return slot() ~= nil
		end),
		Position = Computed(function()
			return UDim2.new(0.5, distance(), 0.5, 0)
		end),
		BackgroundColor3 = Computed(function()
			return if kind:get() == "further" then Theme.colors.panel else Theme.colors.slateLight
		end),
		BorderSizePixel = 0,
		ZIndex = Computed(function()
			return if near:get() then 11 else 10
		end),
		[Children] = {
			New("UIScale")({
				Scale = Computed(function()
					local s = Carousel.scaleAt(distance(), UI.pitch, UI.sideScale)
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
					return if kind:get() == "further" then 2 else 4
				end),
				Transparency = Computed(function()
					return if kind:get() == "further" then 0.5 else 0
				end),
				Color = Computed(function()
					local k, m = kind:get(), mode:get()
					if k == "further" then
						return Theme.colors.muted
					end
					return if m == "Gems" and not limited then PINK else Color3.fromHex(tier.color)
				end),
			}),
			-- Egg art: the variant for the current mode (Gem eggs carry the gem crystal); a
			-- desaturated silhouette when further locked. Rebuilt only when mode or state changes.
			Computed(function()
				local m, k = mode:get(), kind:get()
				return Viewport.new({
					Build = function()
						return MutantModel.buildEgg(eggOf(m), 1, {})
					end,
					Spin = k ~= "further",
					Silhouette = k == "further",
					Size = if limited then UDim2.fromOffset(150, 86) else UDim2.fromOffset(150, 140),
					Position = UDim2.new(0.5, 0, 0, if limited then 90 else 34),
					AnchorPoint = Vector2.new(0.5, 0),
					ZIndex = 11,
				})
			end, Fusion.cleanup),
			-- The tier's name in both modes ("Swamp Egg"): the gem is on the icon and the badge,
			-- and a longer "Swamp Gem Egg" would fall under the readable size on phones.
			C.label({
				Name = "Title",
				Text = tier.name,
				Position = UDim2.fromOffset(8, 178),
				Size = UDim2.new(1, -16, 0, 34),
				MaxTextSize = 30,
				TextColor3 = Computed(function()
					return if kind:get() == "further" then Theme.colors.muted else Theme.colors.white
				end),
				ZIndex = 12,
			}),
			-- Under the name: the shortfall / grow info (near + buyable), or the unlock condition with
			-- a lock glyph before it.
			-- Further-locked cards are only ever side cards (drawn at sideScale), so their condition
			-- and tagline use FURTHER_TEXT: 14 px on screen at 0.6x.
			C.icon("lock", 24, nil, {
				Position = UDim2.fromOffset(10, 214),
				ZIndex = 12,
				Visible = Computed(function()
					return kind:get() == "further"
				end),
			}),
			C.label({
				Name = "Line",
				Position = Computed(function()
					return UDim2.fromOffset(if kind:get() == "further" then 42 else 8, 214)
				end),
				Size = Computed(function()
					return if kind:get() == "further" then UDim2.new(1, -50, 0, 28) else UDim2.new(1, -16, 0, 20)
				end),
				MaxTextSize = Computed(function()
					return if kind:get() == "further" then FURTHER_TEXT else 17
				end),
				StrokeThickness = 1.5,
				ZIndex = 12,
				Visible = Computed(function()
					local k, n = kind:get(), near:get()
					return k == "further" or (k == "buyable" and n)
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
						return conditionText(base)
					end
					local quantity = if hover and short(sn, m, 5) > 0 then 5 else 1
					local s = short(sn, m, quantity)
					local suffix = if quantity == 5 then " for x5" else ""
					if s > 0 then
						return if currencyOf(m) == "Gems"
							then "Need " .. Format.number(s) .. " more Gems" .. suffix
							else "Earn " .. Format.cash(s) .. " more" .. suffix
					end
					return string.format("Grows %s · sells %s+", growShort(tier.growTime), Format.cash(tier.baseValue))
				end),
			}),
			-- Further locked: the tagline.
			C.label({
				Name = "Tagline",
				Text = tier.tagline,
				Position = UDim2.fromOffset(10, 246),
				Size = UDim2.new(1, -20, 0, 64),
				TextWrapped = true,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = FURTHER_TEXT,
				Visible = Computed(function()
					return kind:get() == "further"
				end),
				ZIndex = 12,
			}),
			-- Near + buyable: price and x5.
			New("Frame")({
				Name = "BuyRow",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 242),
				Size = UDim2.new(1, -16, 0, 68),
				Visible = whenNear("buyable"),
				ZIndex = 12,
				[Children] = {
					priceButton(1, UDim2.new(0.62, -4, 1, 0), UDim2.new()),
					priceButton(5, UDim2.new(0.38, -4, 1, 0), UDim2.new(0.62, 4, 0, 0)),
				},
			}),
			-- Near + next locked: the progress card.
			New("Frame")({
				Name = "Progress",
				Position = UDim2.fromOffset(8, 236),
				Size = UDim2.new(1, -16, 0, 74),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				Visible = whenNear("next"),
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
						Position = UDim2.fromOffset(8, 6),
						Size = UDim2.new(1, -16, 1, -12),
						TextWrapped = true,
						MaxTextSize = 22,
						StrokeThickness = 2,
						ZIndex = 14,
						Text = Computed(function()
							local _, text = progressOf(State.snapshot:get(), base)
							return text
						end),
					}),
				},
			}),
			-- Gem mode: "2x RARITY ODDS" on the focused card only (side cards show egg and name).
			New("Frame")({
				Name = "GemBadge",
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(172, 26),
				BackgroundColor3 = PINK,
				BorderSizePixel = 0,
				Visible = Computed(function()
					local m, n, k = mode:get(), near:get(), kind:get()
					return m == "Gems" and n and k == "buyable" and not limited
				end),
				ZIndex = 13,
				[Children] = C.iconText({
					Icon = "gem",
					IconSize = 16,
					Text = "2x RARITY ODDS",
					Size = UDim2.fromScale(1, 1),
					TextSize = 14,
					StrokeThickness = 1.5,
					Gap = 4,
					ZIndex = 14,
				}),
			}),
			-- Limited: "[pumpkin] ENDS IN 3d 4h", live, full width under the odds button and clear of its
			-- shadow (the egg art is shorter on these cards to make room), so it stays readable on phones.
			if limited
				then New("Frame")({
					Name = "Ends",
					Position = UDim2.fromOffset(8, 53),
					Size = UDim2.new(1, -16, 0, 36),
					BackgroundColor3 = Color3.fromHex(tier.color),
					BorderSizePixel = 0,
					ZIndex = 13,
					[Children] = {
						C.stroke(Theme.colors.ink, 2.5),
						C.iconText({
							Name = "EndsText",
							Icon = tier.glyph,
							IconSize = 20,
							Gap = 4,
							Text = Computed(function()
								return endsIn(tier.endsAt, State.now:get())
							end),
							Size = UDim2.fromScale(1, 1),
							TextSize = 22,
							StrokeThickness = 2,
							ZIndex = 14,
						}),
					},
				})
				else nil,
			-- Odds for the variant on display (near, not further locked).
			C.button({
				Name = "Odds",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(44, 38),
				Color = Theme.colors.navy,
				Text = "%",
				MaxTextSize = 20,
				ZIndex = 15,
				Visible = Computed(function()
					return near:get() and kind:get() ~= "further"
				end),
				OnClick = function()
					showOdds:set(not showOdds:get(false))
				end,
			}),
			New("Frame")({
				Name = "OddsOverlay",
				Visible = Computed(function()
					return showOdds:get() and near:get()
				end),
				Active = true,
				BackgroundColor3 = Theme.colors.slate,
				BackgroundTransparency = 0.03,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(6, 50),
				Size = UDim2.new(1, -12, 1, -56),
				ZIndex = 20,
				[Children] = {
					C.padding(9),
					C.label({
						Text = Computed(function()
							return if mode:get() == "Gems" and not limited then "GEM ODDS" else "HATCH ODDS"
						end),
						Size = UDim2.new(1, 0, 0, 24),
						MaxTextSize = 19,
						ZIndex = 21,
					}),
					Computed(function()
						local m = mode:get()
						return New("Frame")({
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(0, 30),
							Size = UDim2.new(1, 0, 1, -30),
							ZIndex = 21,
							[Children] = oddsList(eggOf(m)),
						})
					end, Fusion.cleanup),
				},
			}),
			-- Unlocked this session: NEW ribbon and a short flash.
			New("Frame")({
				Name = "New",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(-10, if limited then 104 else 46),
				Size = UDim2.fromOffset(80, 32),
				Rotation = -10,
				BackgroundColor3 = Theme.colors.toxic,
				BorderSizePixel = 0,
				Visible = Computed(function()
					local visits, k = ribbons:get()[base] or 0, kind:get()
					return visits > 0 and k == "buyable"
				end),
				ZIndex = 17,
				[Children] = {
					C.stroke(Theme.colors.ink, 3),
					C.label({
						Text = "NEW",
						Size = UDim2.new(1, -10, 1, -8),
						Position = UDim2.fromOffset(5, 4),
						MaxTextSize = 22,
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
			-- A panel-colored veil that fades in with distance, so side cards read at ~60%.
			New("Frame")({
				Name = "Veil",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.colors.panel,
				BackgroundTransparency = Computed(function()
					return 1 - (1 - UI.neighborOpacity) * Carousel.veilAt(distance(), UI.pitch)
				end),
				BorderSizePixel = 0,
				ZIndex = 19,
			}),
		},
	})
end

-- Cash | Gems switch for the title row (not rendered where paid random items are restricted).
local function modeSwitch()
	local function segment(name: string, label: string, icon: string, x: number)
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
				C.iconText({
					Icon = icon,
					IconSize = 16,
					Gap = 4,
					Text = label,
					Size = UDim2.fromScale(1, 1),
					TextSize = 15,
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
			segment("Cash", "CASH", "coin", 0),
			segment("Gems", "GEMS", "gem", 0.5),
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
		Icon = "clover",
		IconAfter = "gem",
		IconSize = 16,
		Text = string.format("LUCK · %d", potion.cost),
		MaxTextSize = 14,
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

local function wireInput(stripRef: any)
	local drag: { startX: number, startOffset: number, moved: boolean, lastX: number, lastT: number, velocity: number }? =
		nil
	local autoTimer, autoDir = 0, 0

	-- Design px per screen px, from the strip's real on-screen width.
	local function designPerPixel(): number
		local strip = stripRef:get(false) :: GuiObject?
		local width = if strip then strip.AbsoluteSize.X else 0
		return if width > 0 then STRIP_WIDTH / width else 1
	end

	-- Keys and the wheel, only while the shop is open, above the camera and character controls,
	-- and always sunk so the camera never turns or zooms on them.
	local ACTION = "EggShopNav"
	local function onAction(_: string, inputState: Enum.UserInputState, input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if inputState == Enum.UserInputState.Change and input.Position.Z ~= 0 then
				motion.armed = false
				goTo(Carousel.wheel(State.shopFocus:get(false), input.Position.Z, slotCount(), focusable))
			end
		elseif inputState == Enum.UserInputState.Begin then
			motion.armed = false
			if input.KeyCode == Enum.KeyCode.Left then
				step(-1)
			elseif input.KeyCode == Enum.KeyCode.Right then
				step(1)
			else
				buyFocused()
			end
		end
		return Enum.ContextActionResult.Sink
	end
	local bound = false
	Observer(State.panel):onChange(function()
		if shopOpen() and not bound then
			bound = true
			ContextActionService:BindActionAtPriority(
				ACTION,
				onAction,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.Left,
				Enum.KeyCode.Right,
				Enum.KeyCode.Return,
				Enum.KeyCode.KeypadEnter,
				Enum.UserInputType.MouseWheel
			)
		elseif not shopOpen() and bound then
			bound = false
			ContextActionService:UnbindAction(ACTION)
		end
	end)

	-- Drag: the strip follows the pointer 1:1; on release it glides to the nearest focusable card
	-- (projected a little along the release velocity, so a flick carries). A press that barely
	-- moves is a tap: tapping a side card brings it to the center.
	UserInputService.InputChanged:Connect(function(input)
		local d = drag
		if
			d
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local x = input.Position.X
			if math.abs(x - d.startX) > UI.tapSlop then
				d.moved = true
			end
			local now = os.clock()
			local dt = now - d.lastT
			if dt > 0 then
				local v = -(x - d.lastX) * designPerPixel() / dt
				d.velocity = d.velocity * 0.6 + v * 0.4
			end
			d.lastX, d.lastT = x, now
			if d.moved then
				local offset = d.startOffset - (x - d.startX) * designPerPixel()
				offset = Carousel.clampDrag(offset, UI.pitch, slotCount(), UI.dragOvershoot)
				motion.target = offset
				State.shopOffset:set(offset)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local d = drag
		if
			not d
			or (
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			)
		then
			return
		end
		drag = nil
		if not d.moved then
			local strip = stripRef:get(false) :: GuiObject?
			if strip then
				local center = strip.AbsolutePosition.X + strip.AbsoluteSize.X / 2
				local at = State.shopOffset:get(false) + (input.Position.X - center) * designPerPixel()
				local i = Carousel.nearest(at, UI.pitch, slotCount())
				if i ~= State.shopFocus:get(false) and focusable(i) then
					goTo(i)
				end
			end
			return
		end
		local velocity = if os.clock() - d.lastT < 0.1 then d.velocity else 0
		local projected = State.shopOffset:get(false) + velocity * UI.flickSeconds
		local dir = if velocity > 1 then 1 elseif velocity < -1 then -1 else 0
		goTo(Carousel.settle(projected, UI.pitch, slotCount(), focusable, dir))
	end)

	local stripApi = {
		begin = function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				motion.armed = false
				drag = {
					startX = input.Position.X,
					startOffset = State.shopOffset:get(false),
					moved = false,
					lastX = input.Position.X,
					lastT = os.clock(),
					velocity = 0,
				}
			end
		end,
	}

	-- The glide, and desktop edge-hover auto-scroll.
	RunService.RenderStepped:Connect(function(dt)
		if not drag then
			local current = State.shopOffset:get(false)
			if current ~= motion.target then
				State.shopOffset:set(Carousel.approach(current, motion.target, dt, UI.snapSeconds))
			end
		end
		local strip = stripRef:get(false) :: GuiObject?
		if not shopOpen() or drag or not strip then
			autoTimer, autoDir = 0, 0
			return
		end
		-- The zone is the strip's own edges (not the arrow buttons beside it).
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local pos, size = strip.AbsolutePosition, strip.AbsoluteSize
		local inside = mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
		local fraction = if size.X > 0 then (mouse.X - pos.X) / size.X else 0.5
		local dir, every =
			Carousel.autoScroll(UI, fraction, inside, UserInputService.MouseEnabled, UserInputService.TouchEnabled)
		if dir == 0 or not every then
			autoTimer, autoDir = 0, 0 -- stops the moment the mouse leaves the zone
			motion.armed = true -- and re-arms after a click/key paused it
			return
		end
		if not motion.armed then
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
	-- Input wiring needs a live client (the UI preview builds this headlessly without one).
	local api: any = nil
	pcall(function()
		api = wireInput(stripRef)
	end)

	-- Every limited egg in the config gets a card (shown only while it's on show this visit),
	-- then the base tiers.
	local cards: { any } = {}
	for _, id in Eggs.limitedOrder do
		table.insert(cards, card({ limited = id }))
	end
	for i = 1, BASE_N do
		table.insert(cards, card({ i = i }))
	end

	local function arrow(dir: number)
		return C.button({
			Name = if dir < 0 then "ArrowLeft" else "ArrowRight",
			AnchorPoint = Vector2.new(if dir < 0 then 0 else 1, 0.5),
			Position = UDim2.new(if dir < 0 then 0 else 1, 0, 0, STRIP_HEIGHT / 2),
			Size = UDim2.fromOffset(UI.arrowSize, UI.arrowSize),
			Color = Theme.colors.navy,
			Text = if dir < 0 then "<" else ">",
			MaxTextSize = 34,
			ZIndex = 12,
			-- Hidden at an end (nothing focusable further that way).
			Visible = Computed(function()
				local f, sn, shown = State.shopFocus:get(), State.snapshot:get(), shownLimited:get()
				local _, _ = sn, shown
				return Carousel.step(f, dir, slotCount(), focusable) ~= f
			end),
			OnClick = function()
				motion.armed = false
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
	-- One dot per slot: limited eggs on show (their own color), then the base tiers.
	local function dot(name: string, slotOf: () -> number?, color: () -> Color3)
		return New("Frame")({
			Name = name,
			LayoutOrder = Computed(function()
				return slotOf() or 0
			end),
			Visible = Computed(function()
				return slotOf() ~= nil
			end),
			BorderSizePixel = 0,
			Size = Computed(function()
				return if State.shopFocus:get() == slotOf() then UDim2.fromOffset(16, 16) else UDim2.fromOffset(11, 11)
			end),
			BackgroundColor3 = Computed(function()
				local c = color()
				return if State.shopFocus:get() == slotOf() then Theme.colors.gold else c
			end),
			[Children] = C.stroke(Theme.colors.muted, 1.5),
		})
	end
	for _, id in Eggs.limitedOrder do
		table.insert(
			dots,
			dot("Dot" .. id, function()
				return table.find(shownLimited:get(), id)
			end, function()
				return Color3.fromHex(Eggs.tiers[id].color)
			end)
		)
	end
	for i = 1, BASE_N do
		table.insert(
			dots,
			dot("Dot" .. i, function()
				return #shownLimited:get() + i
			end, function()
				return if kinds[i]:get() == "buyable" then Theme.colors.cream else Theme.colors.ink
			end)
		)
	end

	return C.panel({
		Title = "Egg Shop",
		Icon = "egg",
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
			[Children] = {
				arrow(-1),
				arrow(1),
				New("TextButton")({
					Name = "Strip",
					Text = "",
					AutoButtonColor = false,
					Selectable = false,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.fromOffset(STRIP_WIDTH, STRIP_HEIGHT),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					ZIndex = 10,
					[Ref] = stripRef,
					[OnEvent("InputBegan")] = function(input)
						if api then
							api.begin(input)
						end
					end,
					[Children] = cards,
				}),
				New("Frame")({
					Name = "Dots",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, STRIP_HEIGHT + 10),
					Size = Computed(function()
						return UDim2.fromOffset((#shownLimited:get() + BASE_N) * 26, 18)
					end),
					BackgroundTransparency = 1,
					ZIndex = 10,
					[Children] = dots,
				}),
			},
		}),
	})
end
