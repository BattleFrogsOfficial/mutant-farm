--!strict
-- The HUD has two states (State.zone, set by ZoneController) so the game stays visible:
--
--   always        top-center: Cash + income rate with a thin payout bar, a Rebirth strip under it
--                 (after your first sale), Gems with the pink +. Top-right: Upgrades, Daily and
--                 Almanac tiles a fixed gap apart (red dots inside the tiles). SHOP bottom-right
--                 (mid-right on touch screens). One toast lane.
--   (the HUD sits below Roblox's top bar; the whole HUD hides while a panel is open)
--   right column  under the tiles, top to bottom, a fixed gap apart: weather (hub; a countdown chip
--                 everywhere from 5 min before an event), Instant Weather (pink, when no event is
--                 near), Starter Bundle (always, while it runs), bag count (plot)
--   plot          egg tray (the biggest thing: owned eggs, one "next egg" tile, 2x Luck, HATCH),
--                 WATER with its drain ring and SHOP at the same size beside it, the Next Up line
--                 above the tray.
--   hub           SHOP grows to the biggest button; weather countdown as plain text; bag worth is
--                 written on the Sell stall's sign (ZoneController).
--
-- Icons are vector glyphs built from frames (UI/Glyphs.lua), never images. Every layout number is
-- in Config/Hud.lua. Color rule: pink (Theme.colors.spend) is only for spending, rarity colors only
-- for rarity, navy for everything else. Size equals priority.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Weather = require(Shared.Config.Weather)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local MutantModel = require(Shared.MutantModel)
local Mutants = require(Shared.Config.Mutants)
local GameConfig = require(Shared.Config.Game)
local Growth = require(Shared.Growth)
local Costs = require(Shared.Costs)
local Products = require(Shared.Config.Products)
local ShopRules = require(Shared.ShopRules)
local State = require(script.Parent.Parent.State)
local Purchase = require(script.Parent.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)
local Glyphs = require(script.Parent.Glyphs)
local L = require(Shared.Config.Hud)

local New, Children, Computed, ForPairs, Observer, Spring, OnEvent =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs, Fusion.Observer, Fusion.Spring, Fusion.OnEvent

local NAVY = Theme.colors.navy
local SPEND = Theme.colors.spend
-- The HUD starts directly below Roblox's top bar (IgnoreGuiInset off): the top bar changes width
-- with chat/menu/voice/platform, so nothing of ours shares its strip. Cash is centered CASH_X off
-- the middle, Gems right after it.
local CASH_X = L.top.cashX
local CASH_W = L.top.cashWidth
local ROW_Y = L.top.y -- the top row, directly under Roblox's top bar
local ROW_H = L.top.height
local EDGE = L.edge
local COLUMN = L.column
local PLOT = L.plotButtons
-- Text right of a glyph: the Cash / Gems amount and the bag count.
local TOP_TEXT_X = L.top.iconInset + L.top.icon + L.top.textGap
local BAG_TEXT_X = COLUMN.bagGlyphInset + COLUMN.bagGlyph + COLUMN.bagText.x
local TRAY = L.tray

local TOTAL_SPECIES = (function()
	local n = 0
	for _ in Mutants.species do
		n += 1
	end
	return n
end)()

local almanacCount = Computed(function()
	local n = 0
	for _ in State.almanac:get() do
		n += 1
	end
	return n
end)
local almanacNew = Computed(function()
	local seen = State.almanacSeen:get()
	return seen >= 0 and almanacCount:get() > seen
end)

-- How far right (design px) the bottom-center tray and Next Up must shift so they clear the chat
-- window in the bottom-left. 0 on most screens; only very narrow phones need it.
local TRAY_HALF = TRAY.width / 2
local function shiftFor(screen: { width: number, height: number, scale: number }): number
	local chatRight = (8 + math.min(TRAY.chatWidth, screen.width * 0.3)) / screen.scale + 10
	local trayLeft = screen.width / screen.scale / 2 - TRAY_HALF
	return math.max(0, math.ceil(chatRight - trayLeft))
end
local trayShift = Computed(function()
	return shiftFor(State.screen:get())
end)

local atPlot = Computed(function()
	return State.zone:get() == "plot"
end)
local inHub = Computed(function()
	return State.zone:get() == "hub"
end)

-- Plot buttons (WATER, SHOP; same size) are always side by side, WATER on the left. Mouse screens:
-- in the bottom-right corner when that clears the egg tray, else (a narrow window) mid-right, like
-- touch screens, where the jump button owns the corner.
-- (Both Computeds read State directly, never each other: Fusion 0.2 can't order a Computed that
-- is first read mid-update, so a touch -> mouse switch would leave SHOP mid-right on stale data.)
local function bottomRowTooNarrow(screen: { width: number, height: number, scale: number }): boolean
	local canvasW = screen.width / screen.scale
	local trayRight = canvasW / 2 + shiftFor(screen) + TRAY_HALF + Theme.shadow
	local waterLeft = canvasW - EDGE - 2 * PLOT.width - PLOT.gap
	return waterLeft < trayRight + PLOT.trayClearance
end
local plotMidRight = Computed(function()
	local touch = State.touch:get()
	local narrow = bottomRowTooNarrow(State.screen:get())
	return touch or narrow
end)
-- SHOP mid-right: always on touch screens; at the plot also when the bottom row has no room.
local shopMidRight = Computed(function()
	local touch = State.touch:get()
	local plot = State.zone:get() == "plot"
	local narrow = bottomRowTooNarrow(State.screen:get())
	return touch or (plot and narrow)
end)

-- "4:12" / "1:02:09"
local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

local function openPanel(name: string)
	State.panel:set(if State.panel:get(false) == name then "none" else name)
end

-- Invisible full-size button on top of a box, for readouts you can tap.
local function hit(onClick: () -> ())
	return New("TextButton")({
		Name = "Hit",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
		[OnEvent("Activated")] = onClick,
	})
end

-- A small square notification marker (rotated 45 degrees) inside a tile's top-right corner.
local function dot(visible: any)
	return New("Frame")({
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -L.tiles.dotInset, 0, L.tiles.dotInset),
		Size = UDim2.fromOffset(L.tiles.dot, L.tiles.dot),
		Rotation = 45,
		BackgroundColor3 = Theme.colors.danger,
		BorderSizePixel = 0,
		Visible = visible,
		ZIndex = 8,
		[Children] = C.stroke(Theme.colors.ink, 2),
	})
end

---------------------------------------------------------------------------- always: top-left

local payoutProgress = Computed(function()
	State.clock:get()
	local snap = State.snapshot:get()
	if not snap or not snap.nextPayoutAt or snap.nextPayoutAt <= 0 then
		return 0
	end
	local left = snap.nextPayoutAt - workspace:GetServerTimeNow()
	return math.clamp(1 - left / (snap.payoutSeconds or 60), 0, 1)
end)
local income = Computed(function()
	local snap = State.snapshot:get()
	return if snap then snap.incomePerMinute or 0 else 0
end)

-- Cash: the balance rolls instead of jumping; under it the income rate and countdown, and a thin
-- bar along the bottom edge filling toward the next pen payout. "+$" pops drop out underneath.
local function cashBox()
	local rolling = Spring(State.cash, 12, 1)
	local snapped = false -- don't count up from $0 on join
	Observer(State.cash):onChange(function()
		if not snapped then
			snapped = true
			rolling:setPosition(State.cash:get(false))
		end
	end)
	local bump = Fusion.Value(0)
	local bumpSpring = Spring(bump, 30, 0.45)
	local box = C.pill({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, CASH_X, 0, ROW_Y),
		Size = UDim2.fromOffset(CASH_W, ROW_H),
		Rim = NAVY,
		Children = {
			New("UIScale")({
				Scale = Computed(function()
					return 1 + bumpSpring:get() * 0.06
				end),
			}),
			Glyphs.new("coin", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, L.top.iconInset, 0.5, L.top.iconNudge),
				Size = L.top.icon,
				ZIndex = 2,
			}),
			C.label({
				Name = "Amount",
				Position = UDim2.fromOffset(TOP_TEXT_X, 4),
				Size = UDim2.new(0.45, -TOP_TEXT_X, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				StrokeThickness = 3,
				ZIndex = 2,
				Text = Computed(function()
					return Format.cash(math.floor(rolling:get() + 0.5))
				end),
			}),
			C.label({
				Name = "Rate",
				Position = UDim2.new(0.45, 0, 0, 11),
				Size = UDim2.new(0.55, -10, 0, 13),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 12,
				ZIndex = 2,
				Text = Computed(function()
					if income:get() <= 0 then
						return "HATCH MUTANTS TO EARN / MIN"
					end
					State.now:get()
					local snap = State.snapshot:get(false)
					local left = if snap then math.max(0, snap.nextPayoutAt - workspace:GetServerTimeNow()) else 0
					return string.format("+%s / MIN · %s", Format.cash(income:get()), clock(left))
				end),
			}),
			New("Frame")({
				Name = "Payout",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = Computed(function()
					return UDim2.new(if income:get() > 0 then payoutProgress:get() else 0, 0, 0, 3)
				end),
				BackgroundColor3 = Theme.colors.cream,
				BorderSizePixel = 0,
				ZIndex = 3,
			}),
		},
	})

	local last: number? = nil
	Observer(State.cash):onChange(function()
		local now = State.cash:get(false)
		local previous = last
		last = now
		local gained = if previous then now - previous else 0
		if gained <= 0 then
			return
		end
		bump:set(1)
		task.delay(0.08, function()
			bump:set(0)
		end)
		local payout = State.lastPayout:get(false)
		local fromPen = payout.amount == gained and State.clock:get(false) - payout.at < 1.5
		local pop = C.label({
			Text = "+" .. Format.cash(gained) .. (if fromPen then " 🐾" else ""),
			TextColor3 = Theme.colors.cream,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 38, 1, 40),
			Size = UDim2.fromOffset(170, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 24,
			StrokeThickness = 3,
			ZIndex = 8,
		})
		local scale = Instance.new("UIScale")
		scale.Scale = 0.3
		scale.Parent = pop
		pop.Parent = box
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		TweenService:Create(pop, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, 38, 1, 76),
			TextTransparency = 1,
		}):Play()
		task.delay(1.2, function()
			pop:Destroy()
		end)
	end)
	return box
end

-- Rebirth progress strip directly under the Cash panel, shown from your first sale (before that
-- it's a number that means nothing yet). Tap: Rebirth panel.
local function rebirthStrip()
	local progress = Computed(function()
		local snap = State.snapshot:get()
		if not snap or not snap.rebirthCost then
			return 0
		end
		return math.clamp(snap.cash / snap.rebirthCost, 0, 1)
	end)
	return New("Frame")({
		Name = "RebirthStrip",
		AnchorPoint = Vector2.new(0.5, 0),
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.5, CASH_X - CASH_W / 2, 0, ROW_Y + ROW_H + 6),
		Size = UDim2.fromOffset(CASH_W - 80, 18),
		BackgroundColor3 = Theme.colors.ink,
		BorderSizePixel = 0,
		Visible = Computed(function()
			local snap = State.snapshot:get()
			return snap ~= nil and snap.stats ~= nil and (snap.stats.sold or 0) > 0
		end),
		[Children] = {
			C.pulse(
				Computed(function()
					return progress:get() >= 1
				end),
				0.04
			),
			New("Frame")({
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.colors.slateLight,
				Size = Computed(function()
					return UDim2.fromScale(progress:get(), 1)
				end),
				ZIndex = 2,
			}),
			C.label({
				Size = UDim2.new(1, -10, 1, -4),
				Position = UDim2.fromOffset(5, 2),
				MaxTextSize = 15,
				StrokeThickness = 1.5,
				ZIndex = 3,
				Text = Computed(function()
					local snap = State.snapshot:get()
					local n = (if snap then snap.rebirths else 0) + 1
					return if progress:get() >= 1
						then string.format("♻ REBIRTH %d READY · TAP", n)
						else string.format("♻ REBIRTH %d · %d%%", n, math.floor(progress:get() * 100))
				end),
			}),
			hit(function()
				openPanel("rebirth")
			end),
		},
	})
end

-- Group member bonus, beside the Rebirth strip under Cash: "👥 +10%" while it applies.
local function groupBadge()
	return New("Frame")({
		Name = "GroupBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, CASH_X + CASH_W / 2, 0, ROW_Y + ROW_H + 6),
		Size = UDim2.fromOffset(72, 18),
		BackgroundColor3 = NAVY,
		BorderSizePixel = 0,
		Visible = Computed(function()
			local snap = State.snapshot:get()
			return snap ~= nil and snap.inGroup == true
		end),
		[Children] = {
			C.stroke(Theme.colors.ink, 2),
			C.label({
				Text = string.format("👥 +%d%%", math.floor(GameConfig.groupCashBonus * 100 + 0.5)),
				Size = UDim2.new(1, -6, 1, -4),
				Position = UDim2.fromOffset(3, 2),
				MaxTextSize = 12,
				StrokeThickness = 1.5,
				ZIndex = 2,
			}),
		},
	})
end

local function gemsBox()
	return C.pill({
		Name = "Gems",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, CASH_X + CASH_W / 2 + L.top.gap + L.top.gemsWidth / 2, 0, ROW_Y),
		Size = UDim2.fromOffset(L.top.gemsWidth, ROW_H),
		Rim = NAVY,
		Children = {
			Glyphs.new("gem", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, L.top.iconInset, 0.5, L.top.iconNudge),
				Size = L.top.icon,
				ZIndex = 2,
			}),
			C.label({
				Name = "Amount",
				Position = UDim2.fromOffset(TOP_TEXT_X, 5),
				Size = UDim2.new(1, -(TOP_TEXT_X + L.top.plusGap + L.top.plus + L.top.plusInset), 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 20,
				StrokeThickness = 2.5,
				ZIndex = 2,
				Text = Computed(function()
					return Format.number(State.gems:get())
				end),
			}),
			C.button({
				Name = "Plus",
				Text = "+",
				Color = SPEND,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -L.top.plusInset, 0.5, -1),
				Size = UDim2.fromOffset(L.top.plus, L.top.plus),
				MaxTextSize = 22,
				ZIndex = 4,
				OnClick = function()
					openPanel("store")
				end,
			}),
		},
	})
end

-- Small tile in the top-right row, `slot` tiles in from the right edge (Almanac 0, Daily 1,
-- Upgrades 2), a fixed L.tiles.gap apart, with a vector glyph and its red dot inside the tile.
local function iconButton(name: string, glyph: string, slot: number, alert: any, onClick: () -> ())
	local T = L.tiles
	return New("Frame")({
		Name = name,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(EDGE + slot * (T.width + T.gap)), 0, ROW_Y),
		Size = UDim2.fromOffset(T.width, ROW_H),
		BackgroundTransparency = 1,
		[Children] = {
			C.button({
				Size = UDim2.fromScale(1, 1),
				Color = NAVY,
				Text = "",
				Pulse = alert,
				OnClick = onClick,
				Children = Glyphs.new(glyph, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, T.glyphShift, 0.5, 0),
					Size = T.glyph,
					ZIndex = 4,
				}),
			}),
			dot(alert),
		},
	})
end

local function dailyButton()
	local ready = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and (snap.daily ~= nil and snap.daily.canClaim or snap.vipGemsReady == true)
	end)
	return iconButton("Daily", "gift", 1, ready, function()
		openPanel("daily")
	end)
end

-- Cash upgrades (growth speed, mutation odds): red dot when you can afford one.
local function upgradesButton()
	local affordable = Computed(function()
		local snap = State.snapshot:get()
		if not snap or not snap.upgradeCosts then
			return false
		end
		for _, cost in snap.upgradeCosts do
			if cost and snap.cash >= cost then
				return true
			end
		end
		return false
	end)
	return iconButton("Upgrades", "arrowUp", 2, affordable, function()
		openPanel("upgrades")
	end)
end

-- Almanac: red dot when new species are waiting.
local function almanacButton()
	return iconButton("Almanac", "book", 0, almanacNew, function()
		State.almanacSeen:set(almanacCount:get(false))
		openPanel("almanac")
	end)
end

---------------------------------------------------------------------------- always: Shop

-- The one hot-colored button. Biggest button on screen in the hub; at the plot, where the egg tray
-- is the priority, it is exactly WATER's size and sits beside it.
local function shopButton()
	return C.button({
		Name = "Shop",
		-- On touch screens the jump button owns the bottom-right corner: Shop moves to mid-right (at
		-- the plot also on a narrow mouse screen, where WATER and SHOP don't fit beside the tray).
		AnchorPoint = Computed(function()
			return if shopMidRight:get() then Vector2.new(1, 0.5) else Vector2.new(1, 1)
		end),
		Position = Computed(function()
			return if shopMidRight:get() then UDim2.new(1, -EDGE, 0.5, 0) else UDim2.new(1, -EDGE, 1, -EDGE)
		end),
		Size = Computed(function()
			return if inHub:get()
				then UDim2.fromOffset(L.shop.hubWidth, L.shop.hubHeight)
				else UDim2.fromOffset(PLOT.width, PLOT.height)
		end),
		Color = SPEND,
		Icon = "🛒",
		Text = "SHOP",
		Studs = true,
		MaxTextSize = Computed(function()
			return if inHub:get() then L.shop.hubText else L.shop.plotText
		end),
		OnClick = function()
			openPanel("store")
		end,
	})
end

---------------------------------------------------------------------------- hub only

-- Weather: "☢ ACID RAIN IN 12:40" as plain text in the hub; from Weather.announceSeconds (5 min)
-- before an event until it ends, a server-wide countdown chip in every zone, in the event's
-- color: "☢ ACID RAIN IN 4:12", then "☢ ACID RAIN NOW · 1:12".
local function weatherText()
	local info = Computed(function()
		State.now:get()
		local w = State.weather:get()
		local now = workspace:GetServerTimeNow()
		local activeEvent = (Weather.events :: any)[w.id]
		if activeEvent and now < w.endsAt then
			return { event = activeEvent, active = true, left = w.endsAt - now }
		end
		local nextEvent = (Weather.events :: any)[w.nextId]
		if nextEvent and w.nextAt > now then
			return { event = nextEvent, active = false, left = w.nextAt - now }
		end
		return nil
	end)
	local soon = Computed(function()
		local i = info:get()
		return i ~= nil and (i.active or i.left <= Weather.announceSeconds)
	end)
	local text = Computed(function()
		local i = info:get()
		if not i then
			return ""
		end
		local name = i.event.icon .. " " .. string.upper(i.event.name)
		return if i.active then name .. " NOW · " .. clock(i.left) else name .. " IN " .. clock(i.left)
	end)
	local color = Computed(function()
		local i = info:get()
		return if i then Color3.fromHex(i.event.color) else Theme.colors.cream
	end)
	return New("Frame")({
		Name = "Weather",
		LayoutOrder = 1,
		Size = Computed(function()
			return UDim2.fromOffset(COLUMN.width, if soon:get() then COLUMN.weatherChipHeight else COLUMN.weatherHeight)
		end),
		BackgroundTransparency = 1,
		Visible = Computed(function()
			-- Read every dependency up front (Fusion 0.2: no Computed first read mid-update).
			local isSoon, hub, i = soon:get(), inHub:get(), info:get()
			return isSoon or (hub and i ~= nil)
		end),
		[Children] = {
			C.label({
				Name = "Plain",
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Right,
				MaxTextSize = 17,
				StrokeThickness = 2.5,
				Visible = Computed(function()
					return not soon:get()
				end),
				Text = text,
			}),
			New("Frame")({
				Name = "Chip",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = soon,
				[Children] = {
					C.pill({
						Size = UDim2.fromScale(1, 1),
						Rim = color,
						Children = {
							C.label({
								Position = UDim2.fromOffset(12, 3),
								Size = UDim2.new(1, -18, 1, -6),
								TextXAlignment = Enum.TextXAlignment.Left,
								MaxTextSize = 17,
								TextColor3 = color,
								StrokeThickness = 2.5,
								Text = text,
								ZIndex = 3,
							}),
						},
					}),
				},
			}),
		},
	})
end

-- One text line of a two-line column button (Instant Weather, Starter Bundle).
local function columnLine(line: { y: number, height: number, text: number }, text: any)
	return C.label({
		Text = text,
		Position = UDim2.fromOffset(COLUMN.lineInset, line.y),
		Size = UDim2.new(1, -2 * COLUMN.lineInset, 0, line.height),
		MaxTextSize = line.text,
		ZIndex = 4,
	})
end

-- The only promo on screen, gone when its timer ends.
local function bundleRibbon()
	local left = Computed(function()
		local snap = State.snapshot:get()
		local endsAt = if snap then snap.bundleOfferEndsAt or 0 else 0
		return endsAt - State.now:get()
	end)
	return New("Frame")({
		Name = "Bundle",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(COLUMN.width, COLUMN.bundleHeight),
		BackgroundTransparency = 1,
		-- Always on screen while the offer runs (hub and plot); gone when the timer ends.
		Visible = Computed(function()
			return left:get() > 0
		end),
		[Children] = C.button({
			Size = UDim2.fromScale(1, 1),
			Color = SPEND,
			Text = "",
			OnClick = function()
				openPanel("store")
			end,
			Children = {
				columnLine(COLUMN.line1, "🎁 STARTER BUNDLE"),
				columnLine(
					COLUMN.line2,
					Computed(function()
						return "ENDS IN " .. clock(left:get())
					end)
				),
			},
		}),
	})
end

---------------------------------------------------------------------------- plot only

-- Tray tiles size to their content: the egg art (TRAY.art), a name line, a badge in the corner,
-- and for the next egg tile a second line under the name.
local function trayTile(props: {
	Name: string,
	LayoutOrder: number,
	EggId: string,
	Width: number,
	Badge: string,
	BadgeColor: Color3?,
	BadgeWidth: number,
	Label: string,
	LabelBottom: number,
	Sub: string?,
	Selected: any,
	OnClick: () -> (),
})
	local lift = Spring(
		Computed(function()
			return if props.Selected and props.Selected:get() then -TRAY.lift else 0
		end),
		35,
		0.6
	)
	local children: { any } = {
		Viewport.new({
			Build = function()
				return MutantModel.buildEgg(props.EggId, 1, {})
			end,
			Spin = true,
			SpinSpeed = 1.4,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(TRAY.art, TRAY.art),
			Position = UDim2.new(0.5, 0, 0, TRAY.artY),
			ZIndex = 4,
		}),
		C.label({
			Name = "Label",
			Text = props.Label,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -props.LabelBottom),
			Size = UDim2.new(1, -2 * TRAY.labelInset, 0, TRAY.labelHeight),
			MaxTextSize = TRAY.labelText,
			ZIndex = 4,
		}),
		New("Frame")({
			Name = "Count",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -TRAY.badgeInset, 0, TRAY.badgeInset),
			Size = UDim2.fromOffset(props.BadgeWidth, TRAY.badgeHeight),
			BackgroundColor3 = Theme.colors.ink,
			BorderSizePixel = 0,
			ZIndex = 5,
			[Children] = C.label({
				Text = props.Badge,
				Size = UDim2.new(1, -4, 1, -2),
				Position = UDim2.fromOffset(2, 1),
				TextColor3 = props.BadgeColor or Theme.colors.white,
				MaxTextSize = TRAY.badgeText,
				ZIndex = 6,
			}),
		}),
	}
	if props.Sub then
		table.insert(
			children,
			C.label({
				Name = "Sub",
				Text = props.Sub,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -TRAY.labelInset),
				Size = UDim2.new(1, -2 * TRAY.nextShopInset, 0, TRAY.nextShopHeight),
				MaxTextSize = TRAY.nextShopText,
				TextColor3 = Theme.colors.cream,
				ZIndex = 4,
			})
		)
	end
	return New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(props.Width, TRAY.tileHeight),
		BackgroundTransparency = 1,
		[Children] = New("Frame")({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = Computed(function()
				return UDim2.fromOffset(0, lift:get())
			end),
			[Children] = C.button({
				Size = UDim2.fromScale(1, 1),
				Color = NAVY,
				Text = "",
				Selected = props.Selected,
				OnClick = props.OnClick,
				Children = children,
			}),
		}),
	})
end

-- "SWAMP" for the Swamp Egg.
local function shortName(eggId: string): string
	return string.upper((Eggs.tiers[eggId].name:gsub(" Egg", "")))
end

-- One owned egg: tap to pick it, then tap soil to plant.
local function eggCard(eggId: string, count: number)
	local tier = Eggs.tiers[eggId]
	return trayTile({
		Name = eggId,
		-- Cash eggs first, then Gem eggs, each in tier order, then limited eggs.
		LayoutOrder = table.find(Eggs.order, eggId) or (if table.find(Eggs.gemOrder, eggId)
			then (table.find(Eggs.gemOrder, eggId) :: number) + 10
			else nil) or ((table.find(Eggs.limitedOrder, eggId) or 0) + 20),
		EggId = eggId,
		Width = TRAY.tileWidth,
		Badge = "x" .. count,
		BadgeWidth = TRAY.badgeWidth,
		-- Limited eggs carry their icon ("🎃 PUMPKIN").
		Label = (if tier.icon then tier.icon .. " " else "") .. shortName(eggId),
		LabelBottom = TRAY.labelInset,
		Selected = Computed(function()
			return State.selectedEgg:get() == eggId
		end),
		OnClick = function()
			State.selectedEgg:set(eggId)
		end,
	})
end

-- The one "next egg" tile after the owned eggs: the cheapest unlocked Cash egg you have none of
-- (ShopRules.nextTrayEgg), with its name, its price and "AT THE EGG SHOP". Tap: Egg Shop. Gated
-- tiers never show here; Lab's $25K progress lives in the shop carousel and Next Up.
local function nextEggCard(eggId: string)
	return trayTile({
		Name = "NextEgg",
		LayoutOrder = 100,
		EggId = eggId,
		Width = TRAY.nextTileWidth,
		Badge = Format.cash(Eggs.tiers[eggId].cost),
		BadgeColor = Theme.colors.gold,
		BadgeWidth = TRAY.nextBadgeWidth,
		Label = shortName(eggId),
		LabelBottom = TRAY.nextNameBottom,
		Sub = "AT THE EGG SHOP",
		OnClick = function()
			openPanel("shop")
		end,
	})
end

-- 2x Luck pass on the tray: it sells at the hatch moment. Pink while for sale, navy once owned.
local function luckBadge()
	local owned = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and snap.ownedPasses ~= nil and snap.ownedPasses.Luck2x == true
	end)
	return New("TextButton")({
		Name = "LuckBadge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(104, 28),
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		BackgroundColor3 = Computed(function()
			return if owned:get() then NAVY else SPEND
		end),
		ZIndex = 4,
		[OnEvent("Activated")] = function()
			if not owned:get(false) then
				Purchase.pass("Luck2x")
			end
		end,
		[Children] = {
			C.stroke(Theme.colors.ink, 2.5),
			C.bevel(3, 0.55),
			C.label({
				Text = Computed(function()
					return if owned:get() then "✅ 2x LUCK" else "🔒 2x LUCK"
				end),
				Size = UDim2.new(1, -8, 1, -6),
				Position = UDim2.fromOffset(4, 3),
				MaxTextSize = 14,
				ZIndex = 5,
			}),
		},
	})
end

-- Skip Timer (Gems): finish every growing egg now. Shows only on long waits (2+ minutes left);
-- not enough Gems opens the Shop.
local SKIP_SHOW_AFTER = 120
local function skipBadge()
	local info = Computed(function()
		local snap = State.snapshot:get()
		local now = State.now:get()
		if not snap then
			return { cost = 0, longest = 0 }
		end
		local cost, longest = 0, 0
		for _, slot in snap.slots do
			local left = Growth.secondsRemaining(
				State.slotGrowth(snap, slot, now),
				slot.required,
				now,
				snap.wateredUntil,
				snap.speed
			)
			longest = math.max(longest, left)
			cost += Costs.skip(left, Products.gems.SkipTimer.costPer10Minutes)
		end
		return { cost = cost, longest = longest }
	end)
	return New("TextButton")({
		Name = "SkipBadge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -122, 0, 0),
		Size = UDim2.fromOffset(98, 28),
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		BackgroundColor3 = SPEND,
		Visible = Computed(function()
			return info:get().longest >= SKIP_SHOW_AFTER
		end),
		ZIndex = 4,
		[OnEvent("Activated")] = function()
			local i = info:get(false)
			if State.gems:get(false) < i.cost then
				State.toast(string.format("Need %d Gems to finish now", i.cost), "info")
				openPanel("store")
				return
			end
			Remotes.get("SkipTimers"):FireServer()
		end,
		[Children] = {
			C.stroke(Theme.colors.ink, 2.5),
			C.bevel(3, 0.55),
			C.label({
				Text = Computed(function()
					return string.format("⏩ %d 💎", info:get().cost)
				end),
				Size = UDim2.new(1, -8, 1, -6),
				Position = UDim2.fromOffset(4, 3),
				MaxTextSize = 14,
				ZIndex = 5,
			}),
		},
	})
end

-- HATCH inside the tray: "HATCH 3" when eggs are ready, dimmed otherwise.
local function hatchButton()
	local ready = Computed(function()
		return State.readyCount:get() > 0
	end)
	return C.button({
		Name = "Hatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -TRAY.hatchInset, 0.5, 10),
		Size = UDim2.fromOffset(TRAY.hatchWidth, TRAY.tileHeight),
		Color = NAVY,
		Text = "",
		Studs = true,
		Disabled = Computed(function()
			return not ready:get()
		end),
		Pulse = ready,
		Selected = ready,
		OnClick = function()
			if ready:get(false) then
				Remotes.get("HarvestAll"):FireServer()
			end
		end,
		Children = {
			Glyphs.new("egg", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, -L.glyph.shadow / 2, 0, TRAY.hatchGlyphY),
				Size = TRAY.hatchGlyph,
				ZIndex = 4,
			}),
			C.label({
				Text = Computed(function()
					local n = State.readyCount:get()
					return if n > 0 then string.format("HATCH %d", n) else "HATCH"
				end),
				Position = UDim2.fromOffset(6, TRAY.hatchLine1.y),
				Size = UDim2.new(1, -12, 0, TRAY.hatchLine1.height),
				MaxTextSize = TRAY.hatchLine1.text,
				ZIndex = 4,
			}),
			C.label({
				-- No countdown here: each egg already shows its own timer above it.
				Text = Computed(function()
					return if ready:get() then "TAP!" else "GROWING"
				end),
				Position = UDim2.fromOffset(6, TRAY.hatchLine2.y),
				Size = UDim2.new(1, -12, 0, TRAY.hatchLine2.height),
				MaxTextSize = TRAY.hatchLine2.text,
				TextColor3 = Theme.colors.cream,
				ZIndex = 4,
			}),
		},
	})
end

local function eggTray()
	-- Owned eggs only (a count of 0 isn't owned).
	local eggs = Computed(function()
		local snap = State.snapshot:get()
		local out = {}
		for id, count in if snap then snap.eggs else {} do
			if count > 0 then
				out[id] = count
			end
		end
		return out
	end)
	local hasEggs = Computed(function()
		return next(eggs:get()) ~= nil
	end)
	-- { [eggId] = true } for the one next-egg tile (a map so the tile rebuilds when it changes).
	local nextEgg = Computed(function()
		local snap = State.snapshot:get()
		if not snap then
			return {}
		end
		local id = ShopRules.nextTrayEgg(snap.eggs, snap.rebirths, snap.stats.totalCashEarned or 0)
		return if id then { [id] = true } else {}
	end)
	return New("Frame")({
		Name = "EggTray",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = Computed(function()
			return UDim2.new(0.5, trayShift:get(), 1, -TRAY.bottom)
		end),
		Size = UDim2.fromOffset(TRAY.width, TRAY.height),
		BackgroundTransparency = 1,
		Visible = atPlot,
		[Children] = {
			C.shadow(),
			New("Frame")({
				Name = "Tray",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 1,
				[Children] = {
					C.stroke(Theme.colors.ink, 3),
					C.gradient(Theme.colors.panelHi, Theme.colors.panel),
				},
			}),
			New("Frame")({
				Name = "Tab",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.fromOffset(180, 26),
				BackgroundColor3 = NAVY,
				BorderSizePixel = 0,
				ZIndex = 3,
				[Children] = {
					C.stroke(Theme.colors.ink, 2.5),
					C.label({
						Size = UDim2.new(1, -16, 1, -6),
						Position = UDim2.fromOffset(8, 3),
						MaxTextSize = 14,
						ZIndex = 4,
						Text = Computed(function()
							return if hasEggs:get() then "PICK AN EGG · TAP SOIL" else "OUT OF EGGS"
						end),
					}),
				},
			}),
			luckBadge(),
			skipBadge(),
			New("ScrollingFrame")({
				Name = "Cards",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(10, 24),
				Size = UDim2.new(1, -(TRAY.hatchWidth + 24), 1, -30),
				ScrollBarThickness = 4,
				ScrollingDirection = Enum.ScrollingDirection.X,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				ZIndex = 2,
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, TRAY.tileGap),
					}),
					New("UIPadding")({ PaddingLeft = UDim.new(0, 2) }),
					ForPairs(eggs, function(eggId: string, count: number)
						return eggId, eggCard(eggId, count)
					end, Fusion.cleanup),
					ForPairs(nextEgg, function(eggId: string)
						return eggId, nextEggCard(eggId)
					end, Fusion.cleanup),
				},
			}),
			hatchButton(),
		},
	})
end

-- WATER: one tap waters the whole plot (GameConfig.waterMultiplier for waterDuration). A square
-- drain ring empties clockwise while it lasts and the button is dimmed meanwhile (navy, never pink:
-- it's free). The first tap in a session explains it in a toast. The label is "WATER · 2x 30s" on
-- two lines, the line break standing in for the dot: "WATER" / "2x 30s".
-- 2 -> "2", 1.5 -> "1.5" (config values may be fractional; %d would throw on them).
local function plainNumber(n: number): string
	return if n == math.floor(n) then tostring(math.floor(n)) else tostring(n)
end
local WATER_BOOST = plainNumber(GameConfig.waterMultiplier) .. "x"
local WATER_SUB = "· " .. WATER_BOOST .. " " .. plainNumber(GameConfig.waterDuration) .. "s"
local WATER_TOAST = "Watered! Eggs grow "
	.. WATER_BOOST
	.. " faster for "
	.. plainNumber(GameConfig.waterDuration)
	.. " s."
local wateredThisSession = false

local function waterButton()
	local watering = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and State.now:get() < snap.wateredUntil
	end)
	local left = Computed(function()
		State.clock:get()
		local snap = State.snapshot:get()
		if not snap then
			return 0
		end
		return math.clamp((snap.wateredUntil - workspace:GetServerTimeNow()) / GameConfig.waterDuration, 0, 1)
	end)
	local growing = Computed(function()
		return State.nextReadyIn:get() ~= nil
	end)
	local TEXT_X = PLOT.glyphInset + PLOT.glyph + PLOT.textGap
	-- One edge of the ring: its quarter of `left`, in order top, right, bottom, left.
	local RING = PLOT.ringWidth
	local ANCHORS = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(1, 1), Vector2.new(0, 1) }
	local function edge(i: number)
		local fill = Computed(function()
			return math.clamp(left:get() * 4 - (i - 1), 0, 1)
		end)
		local horizontal = i % 2 == 1
		return New("Frame")({
			Name = "Ring" .. i,
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.colors.water,
			Visible = watering,
			ZIndex = 6,
			AnchorPoint = ANCHORS[i],
			Position = UDim2.fromScale(ANCHORS[i].X, ANCHORS[i].Y),
			Size = Computed(function()
				return if horizontal then UDim2.new(fill:get(), 0, 0, RING) else UDim2.new(0, RING, fill:get(), 0)
			end),
		})
	end
	return New("Frame")({
		Name = "Water",
		-- Left of SHOP, the same size; bottom-right, or mid-right with SHOP (plotMidRight).
		AnchorPoint = Computed(function()
			return if plotMidRight:get() then Vector2.new(1, 0.5) else Vector2.new(1, 1)
		end),
		Position = Computed(function()
			local beside = -(EDGE + PLOT.width + PLOT.gap)
			return if plotMidRight:get() then UDim2.new(1, beside, 0.5, 0) else UDim2.new(1, beside, 1, -EDGE)
		end),
		Size = UDim2.fromOffset(PLOT.width, PLOT.height),
		BackgroundTransparency = 1,
		Visible = atPlot,
		[Children] = {
			C.button({
				Size = UDim2.fromScale(1, 1),
				Color = NAVY,
				Text = "",
				Disabled = watering,
				Pulse = Computed(function()
					local isWatering, isGrowing = watering:get(), growing:get()
					return not isWatering and isGrowing
				end),
				Selected = Computed(function()
					return State.objective:get().ui == "Water"
				end),
				OnClick = function()
					Remotes.get("Water"):FireServer()
					if not wateredThisSession then
						wateredThisSession = true
						State.toast(WATER_TOAST, "info")
					end
				end,
				Children = {
					Glyphs.new("drop", {
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, PLOT.glyphInset, 0.5, L.top.iconNudge),
						Size = PLOT.glyph,
						ZIndex = 4,
					}),
					C.label({
						Name = "Label",
						Text = "WATER",
						Position = UDim2.fromOffset(TEXT_X, PLOT.line1.y),
						Size = UDim2.new(1, -(TEXT_X + PLOT.textRight), 0, PLOT.line1.height),
						MaxTextSize = PLOT.line1.text,
						ZIndex = 4,
					}),
					C.label({
						Name = "Sub",
						-- The label reads "WATER · 2x 30s" over two lines; while watered, the time
						-- left: "· 2x 0:18".
						Text = Computed(function()
							local snap = State.snapshot:get()
							if watering:get() and snap then
								return "· " .. WATER_BOOST .. " " .. clock(snap.wateredUntil - State.now:get())
							end
							return WATER_SUB
						end),
						Position = UDim2.fromOffset(TEXT_X, PLOT.line2.y),
						Size = UDim2.new(1, -(TEXT_X + PLOT.textRight), 0, PLOT.line2.height),
						MaxTextSize = PLOT.line2.text,
						TextColor3 = Theme.colors.cream,
						ZIndex = 4,
					}),
				},
			}),
			edge(1),
			edge(2),
			edge(3),
			edge(4),
		},
	})
end

-- One line right above the tray: "⭐ NEXT SOIL PATCH: $675 ▮▮▮▯". Also in the hub while a
-- tutorial step points there.
local function nextUp()
	local objective = State.objective
	local SEGMENTS = 8
	local segments: { any } = {
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}
	for i = 1, SEGMENTS do
		table.insert(
			segments,
			New("Frame")({
				LayoutOrder = i,
				Size = UDim2.fromOffset(9, 16),
				BorderSizePixel = 0,
				BackgroundColor3 = Computed(function()
					local p = objective:get().progress or 0
					return if p >= i / SEGMENTS - 1e-6 then Theme.colors.cream else Theme.colors.ink
				end),
				ZIndex = 3,
			})
		)
	end
	return New("Frame")({
		Name = "NextUp",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = Computed(function()
			return UDim2.new(0.5, trayShift:get(), 1, -L.nextUpBottom)
		end),
		Size = UDim2.fromOffset(400, 32),
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = Computed(function()
			local o, plot = objective:get(), atPlot:get()
			return o.text ~= "" and (plot or o.hub == true)
		end),
		[Children] = {
			C.stroke(Theme.colors.ink, 3),
			C.label({
				Text = Computed(function()
					return "⭐ " .. string.upper(objective:get().text)
				end),
				Position = UDim2.fromOffset(10, 5),
				Size = Computed(function()
					return if objective:get().progress ~= nil
						then UDim2.new(1, -120, 1, -10)
						else UDim2.new(1, -20, 1, -10)
				end),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
				ZIndex = 2,
			}),
			New("Frame")({
				Name = "Segments",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(SEGMENTS * 12, 18),
				BackgroundTransparency = 1,
				Visible = Computed(function()
					return objective:get().progress ~= nil
				end),
				ZIndex = 2,
				[Children] = segments,
			}),
		},
	})
end

-- Bag count, last in the right column, plot only (its worth is on the Sell stall's sign in the hub).
local function bagChip()
	local count = Computed(function()
		local snap = State.snapshot:get()
		local n = 0
		if snap then
			for _ in snap.inventory do
				n += 1
			end
		end
		return { n = n, cap = if snap then snap.inventoryCap else 0 }
	end)
	return New("Frame")({
		Name = "BagChip",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(COLUMN.bagWidth, COLUMN.bagHeight),
		BackgroundTransparency = 1,
		Visible = atPlot,
		[Children] = C.pill({
			Size = UDim2.fromScale(1, 1),
			Rim = Computed(function()
				local c = count:get()
				return if c.cap > 0 and c.n >= c.cap * 0.9 then Theme.colors.danger else NAVY
			end),
			Children = {
				Glyphs.new("bag", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, COLUMN.bagGlyphInset, 0.5, L.top.iconNudge),
					Size = COLUMN.bagGlyph,
					ZIndex = 2,
				}),
				C.label({
					Name = "Count",
					Position = UDim2.fromOffset(BAG_TEXT_X, COLUMN.bagText.y),
					Size = UDim2.new(1, -(BAG_TEXT_X + COLUMN.bagText.right), 1, -2 * COLUMN.bagText.y),
					MaxTextSize = COLUMN.bagText.text,
					ZIndex = 2,
					Text = Computed(function()
						local c = count:get()
						return string.format("%d/%d", c.n, c.cap)
					end),
				}),
			},
		}),
	})
end

-- Instant Weather (pink: it spends Gems), under the weather line: only when no global event runs
-- or starts within Weather.announceSeconds, no plot event of yours runs, and the player may buy
-- paid odds boosts (PolicyService). Opens the picker.
local function instantWeatherButton()
	local shown = Computed(function()
		State.now:get()
		local snap = State.snapshot:get()
		local w = State.weather:get()
		local mine = State.plotWeather:get()
		local now = workspace:GetServerTimeNow()
		local globalSoon = (w.id ~= "" and now < w.endsAt)
			or (w.nextAt > now and w.nextAt - now <= Weather.announceSeconds)
		return snap ~= nil and snap.paidRandomRestricted == false and not globalSoon and mine.id == ""
	end)
	return New("Frame")({
		Name = "InstantWeather",
		LayoutOrder = 2,
		-- The Starter Bundle ribbon's width (the column width), two lines like the ribbon.
		Size = UDim2.fromOffset(COLUMN.width, COLUMN.instantHeight),
		BackgroundTransparency = 1,
		Visible = shown,
		[Children] = C.button({
			Size = UDim2.fromScale(1, 1),
			Color = Theme.colors.spend,
			Text = "",
			OnClick = function()
				openPanel("instantWeather")
			end,
			Children = {
				columnLine(COLUMN.line1, "☢ INSTANT WEATHER"),
				columnLine(COLUMN.line2, Format.number(Products.gems.InstantWeather.cost) .. " 💎"),
			},
		}),
	})
end

-- Right column under the top-right tiles, top to bottom, COLUMN.gap apart: weather, Instant
-- Weather, Starter Bundle (always, while it runs), bag count (plot). Kept off the left side
-- (Roblox's buttons and chat) and narrow enough to stay clear of the toast lane.
local function rightColumn()
	return New("Frame")({
		Name = "RightColumn",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE, 0, ROW_Y + ROW_H + COLUMN.gap),
		Size = UDim2.fromOffset(COLUMN.width, COLUMN.height),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, COLUMN.gap),
			}),
			weatherText(),
			instantWeatherButton(),
			bundleRibbon(),
			bagChip(),
		},
	})
end

return function()
	return {
		-- always
		cashBox(),
		rebirthStrip(),
		groupBadge(),
		gemsBox(),
		dailyButton(),
		almanacButton(),
		upgradesButton(),
		shopButton(),
		-- hub
		rightColumn(),
		-- plot
		eggTray(),
		waterButton(),
		nextUp(),
	}
end
