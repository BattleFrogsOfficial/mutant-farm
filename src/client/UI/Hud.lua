--!strict
-- The HUD has two states (State.zone, set by ZoneController) so the game stays visible:
--
--   always        top-center: Cash + income rate with a thin payout bar, a Rebirth strip under it
--                 (after your first sale), Gems with the pink +. Top-right: Daily and Almanac icons
--                 (red dots). SHOP bottom-right (mid-right on touch screens). One toast lane.
--   (the top row shares the top-bar strip with Roblox's buttons, which keep the top-left corner;
--   the whole HUD hides while a panel is open)
--   right column  weather (hub), Starter Bundle (always, while it runs), bag count (plot)
--   plot          egg tray (the biggest thing: eggs, next locked tier, 2x Luck, HATCH), WATER with
--                 its drain ring, the Next Up line above the tray, bag count top-left.
--   hub           SHOP grows to the biggest button; weather countdown as plain text and the Starter
--                 Bundle ribbon under the top-right icons; bag worth floats over the Sell pad (ZoneController).
--
-- Color rule: pink (Theme.colors.spend) is only for spending, rarity colors only for rarity,
-- navy for everything else. Size equals priority.

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
local State = require(script.Parent.Parent.State)
local Purchase = require(script.Parent.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, ForPairs, Observer, Spring, OnEvent =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs, Fusion.Observer, Fusion.Spring, Fusion.OnEvent

local NAVY = Theme.colors.navy
local SPEND = Theme.colors.spend
-- The top row sits in the top-bar strip itself (IgnoreGuiInset on), right of Roblox's buttons,
-- which keep the top-left corner: currencies top-center, Daily and Almanac top-right. Cash is centered CASH_X off the
-- middle, Gems right after it.
local CASH_X = -70
local CASH_W = 236

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
local TRAY_HALF = 212
local CHAT_WIDTH_PX = 215 -- the chat window at its smallest (WidthScale 0.5), plus margin below
local trayShift = Computed(function()
	local screen = State.screen:get()
	local chatRight = (8 + math.min(CHAT_WIDTH_PX, screen.width * 0.3)) / screen.scale + 10
	local trayLeft = screen.width / screen.scale / 2 - TRAY_HALF
	return math.max(0, math.ceil(chatRight - trayLeft))
end)

local atPlot = Computed(function()
	return State.zone:get() == "plot"
end)
local inHub = Computed(function()
	return State.zone:get() == "hub"
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

-- A small square notification marker (rotated 45°) for a corner.
local function dot(visible: any)
	return New("Frame")({
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(16, 16),
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
		Position = UDim2.new(0.5, CASH_X, 0, 8),
		Size = UDim2.fromOffset(CASH_W, 58),
		Rim = NAVY,
		Children = {
			New("UIScale")({
				Scale = Computed(function()
					return 1 + bumpSpring:get() * 0.06
				end),
			}),
			C.label({
				Text = "💰",
				Position = UDim2.fromOffset(10, 9),
				Size = UDim2.fromOffset(38, 38),
				MaxTextSize = 30,
				ZIndex = 2,
			}),
			C.label({
				Name = "Amount",
				Position = UDim2.fromOffset(54, 5),
				Size = UDim2.new(1, -62, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 28,
				StrokeThickness = 3,
				ZIndex = 2,
				Text = Computed(function()
					return Format.cash(math.floor(rolling:get() + 0.5))
				end),
			}),
			C.label({
				Name = "Rate",
				Position = UDim2.fromOffset(54, 35),
				Size = UDim2.new(1, -62, 0, 14),
				TextXAlignment = Enum.TextXAlignment.Left,
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
					return UDim2.new(if income:get() > 0 then payoutProgress:get() else 0, 0, 0, 4)
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
			Position = UDim2.new(0, 54, 1, 34),
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
			Position = UDim2.new(0, 54, 1, 70),
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
		Position = UDim2.new(0.5, CASH_X, 0, 72),
		Size = UDim2.fromOffset(CASH_W, 22),
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

local function gemsBox()
	return C.pill({
		Name = "Gems",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, CASH_X + CASH_W / 2 + 8 + 66, 0, 8),
		Size = UDim2.fromOffset(132, 58),
		Rim = NAVY,
		Children = {
			C.label({
				Text = "💎",
				Position = UDim2.fromOffset(9, 11),
				Size = UDim2.fromOffset(34, 34),
				MaxTextSize = 26,
				ZIndex = 2,
			}),
			C.label({
				Name = "Amount",
				Position = UDim2.fromOffset(46, 8),
				Size = UDim2.new(1, -90, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 22,
				StrokeThickness = 2.5,
				ZIndex = 2,
				Text = Computed(function()
					return Format.number(State.gems:get())
				end),
			}),
			C.label({
				Text = "GEMS",
				Position = UDim2.fromOffset(46, 35),
				Size = UDim2.new(1, -90, 0, 13),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 11,
				ZIndex = 2,
			}),
			C.button({
				Name = "Plus",
				Text = "+",
				Color = SPEND,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -7, 0.5, 0),
				Size = UDim2.fromOffset(36, 42),
				MaxTextSize = 28,
				ZIndex = 4,
				OnClick = function()
					openPanel("store")
				end,
			}),
		},
	})
end

-- Small square icon in the top-right row; `fromRight` = its right edge's distance from the edge.
local function iconButton(name: string, icon: string, fromRight: number, alert: any, onClick: () -> ())
	return New("Frame")({
		Name = name,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -fromRight, 0, 8),
		Size = UDim2.fromOffset(52, 58),
		BackgroundTransparency = 1,
		[Children] = {
			C.button({
				Size = UDim2.fromScale(1, 1),
				Color = NAVY,
				Text = icon,
				MaxTextSize = 28,
				Pulse = alert,
				OnClick = onClick,
			}),
			dot(alert),
		},
	})
end

local function dailyButton()
	local ready = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and snap.daily ~= nil and snap.daily.canClaim
	end)
	return iconButton("Daily", "🎁", 74, ready, function()
		openPanel("daily")
	end)
end

-- Almanac: a small icon like Daily, with a red dot when new species are waiting.
local function almanacButton()
	return iconButton("Almanac", "📖", 14, almanacNew, function()
		State.almanacSeen:set(almanacCount:get(false))
		openPanel("almanac")
	end)
end

---------------------------------------------------------------------------- always: Shop

-- The one hot-colored button. Biggest thing on screen in the hub; smaller at the plot, where the
-- egg tray is the priority.
local function shopButton()
	return C.button({
		Name = "Shop",
		-- On touch screens the jump button owns the bottom-right corner: Shop moves to mid-right.
		AnchorPoint = Computed(function()
			return if State.touch:get() then Vector2.new(1, 0.5) else Vector2.new(1, 1)
		end),
		Position = Computed(function()
			return if State.touch:get() then UDim2.new(1, -14, 0.5, 0) else UDim2.new(1, -14, 1, -14)
		end),
		Size = Computed(function()
			return if inHub:get() then UDim2.fromOffset(230, 88) else UDim2.fromOffset(150, 62)
		end),
		Color = SPEND,
		Icon = "🛒",
		Text = "SHOP",
		MaxTextSize = Computed(function()
			return if inHub:get() then 36 else 24
		end),
		OnClick = function()
			openPanel("store")
		end,
	})
end

---------------------------------------------------------------------------- hub only

-- "☢ ACID RAIN IN 4:12", or "☢ ACID RAIN NOW · 1:12" while it runs. Plain text, no box.
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
	return C.label({
		Name = "Weather",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(250, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 17,
		StrokeThickness = 2.5,
		Visible = Computed(function()
			return inHub:get() and info:get() ~= nil
		end),
		Text = Computed(function()
			local i = info:get()
			if not i then
				return ""
			end
			local name = i.event.icon .. " " .. string.upper(i.event.name)
			return if i.active then name .. " NOW · " .. clock(i.left) else name .. " IN " .. clock(i.left)
		end),
	})
end

-- The only promo on screen, hub only, gone when its timer ends.
local function bundleRibbon()
	local left = Computed(function()
		local snap = State.snapshot:get()
		local endsAt = if snap then snap.bundleOfferEndsAt or 0 else 0
		return endsAt - State.now:get()
	end)
	return New("Frame")({
		Name = "Bundle",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(176, 54),
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
				C.label({
					Text = "🎁 STARTER BUNDLE",
					Position = UDim2.fromOffset(6, 4),
					Size = UDim2.new(1, -12, 0, 18),
					MaxTextSize = 15,
					ZIndex = 4,
				}),
				C.label({
					Text = Computed(function()
						return "ENDS IN " .. clock(left:get())
					end),
					Position = UDim2.fromOffset(6, 24),
					Size = UDim2.new(1, -12, 0, 14),
					MaxTextSize = 12,
					ZIndex = 4,
				}),
			},
		}),
	})
end

---------------------------------------------------------------------------- plot only

local function eggCard(eggId: string, count: number)
	local tier = Eggs.tiers[eggId]
	local selected = Computed(function()
		return State.selectedEgg:get() == eggId
	end)
	local lift = Spring(
		Computed(function()
			return if selected:get() then -8 else 0
		end),
		35,
		0.6
	)
	return New("Frame")({
		Name = eggId,
		LayoutOrder = table.find(Eggs.order, eggId),
		Size = UDim2.fromOffset(88, 104),
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
				Selected = selected,
				OnClick = function()
					State.selectedEgg:set(eggId)
				end,
				Children = {
					Viewport.new({
						Build = function()
							return MutantModel.buildEgg(eggId, 1, {})
						end,
						Spin = true,
						SpinSpeed = 1.4,
						Size = UDim2.new(1, -10, 1, -32),
						Position = UDim2.fromOffset(5, 3),
						ZIndex = 4,
					}),
					C.label({
						Text = string.upper((tier.name:gsub(" Egg", ""))),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -5),
						Size = UDim2.new(1, -8, 0, 20),
						MaxTextSize = 15,
						ZIndex = 4,
					}),
					New("Frame")({
						Name = "Count",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -3, 0, 3),
						Size = UDim2.fromOffset(36, 22),
						BackgroundColor3 = Theme.colors.ink,
						BorderSizePixel = 0,
						ZIndex = 5,
						[Children] = C.label({
							Text = "x" .. count,
							Size = UDim2.fromScale(1, 1),
							MaxTextSize = 15,
							ZIndex = 6,
						}),
					}),
				},
			}),
		}),
	})
end

-- The next tier you can't buy yet, greyed with a padlock: something to aim for. Opens Rebirth.
local function lockedCard()
	local nextTier = Computed(function()
		local snap = State.snapshot:get()
		local rebirths = if snap then snap.rebirths else 0
		for _, eggId in Eggs.order do
			if Eggs.tiers[eggId].unlockRebirth > rebirths then
				return eggId
			end
		end
		return nil
	end)
	return New("Frame")({
		Name = "Locked",
		LayoutOrder = 100,
		Size = UDim2.fromOffset(88, 104),
		BackgroundTransparency = 1,
		Visible = Computed(function()
			return nextTier:get() ~= nil
		end),
		[Children] = C.button({
			Size = UDim2.fromScale(1, 1),
			Color = Theme.colors.locked,
			Text = "",
			OnClick = function()
				openPanel("rebirth")
			end,
			Children = {
				C.padlock({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.fromOffset(30, 36),
					Color = Theme.colors.cream,
					ZIndex = 4,
				}),
				C.label({
					Text = Computed(function()
						local id = nextTier:get()
						return if id then string.upper((Eggs.tiers[id].name:gsub(" Egg", ""))) else ""
					end),
					Position = UDim2.new(0, 4, 0, 50),
					Size = UDim2.new(1, -8, 0, 18),
					MaxTextSize = 15,
					ZIndex = 4,
				}),
				C.label({
					Text = Computed(function()
						local id = nextTier:get()
						return if id then "REBIRTH " .. Eggs.tiers[id].unlockRebirth else ""
					end),
					Position = UDim2.new(0, 4, 0, 70),
					Size = UDim2.new(1, -8, 0, 14),
					MaxTextSize = 12,
					TextColor3 = Theme.colors.cream,
					ZIndex = 4,
				}),
			},
		}),
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

-- HATCH inside the tray: "HATCH 3" when eggs are ready, dimmed otherwise.
local function hatchButton()
	local ready = Computed(function()
		return State.readyCount:get() > 0
	end)
	return C.button({
		Name = "Hatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 10),
		Size = UDim2.fromOffset(108, 104),
		Color = NAVY,
		Text = "",
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
			C.label({
				Text = "🥚",
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 36),
				MaxTextSize = 30,
				ZIndex = 4,
			}),
			C.label({
				Text = Computed(function()
					local n = State.readyCount:get()
					return if n > 0 then string.format("HATCH %d", n) else "HATCH"
				end),
				Position = UDim2.fromOffset(6, 48),
				Size = UDim2.new(1, -12, 0, 20),
				MaxTextSize = 18,
				ZIndex = 4,
			}),
			C.label({
				-- No countdown here: each egg already shows its own timer above it.
				Text = Computed(function()
					return if ready:get() then "TAP!" else "GROWING"
				end),
				Position = UDim2.fromOffset(6, 70),
				Size = UDim2.new(1, -12, 0, 16),
				MaxTextSize = 14,
				TextColor3 = Theme.colors.cream,
				ZIndex = 4,
			}),
		},
	})
end

local function eggTray()
	local eggs = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.eggs else {}
	end)
	local hasEggs = Computed(function()
		return next(eggs:get()) ~= nil
	end)
	return New("Frame")({
		Name = "EggTray",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = Computed(function()
			return UDim2.new(0.5, trayShift:get(), 1, -12)
		end),
		Size = UDim2.fromOffset(TRAY_HALF * 2, 146),
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
				Size = UDim2.fromOffset(200, 26),
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
			New("ScrollingFrame")({
				Name = "Cards",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(10, 24),
				Size = UDim2.new(1, -132, 1, -30),
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
						Padding = UDim.new(0, 10),
					}),
					New("UIPadding")({ PaddingLeft = UDim.new(0, 2) }),
					ForPairs(eggs, function(eggId: string, count: number)
						return eggId, eggCard(eggId, count)
					end, Fusion.cleanup),
					lockedCard(),
				},
			}),
			hatchButton(),
		},
	})
end

-- Water with a drain "ring": a square outline that empties clockwise while 2x lasts.
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
		return math.clamp((snap.wateredUntil - workspace:GetServerTimeNow()) / 30, 0, 1)
	end)
	local growing = Computed(function()
		return State.nextReadyIn:get() ~= nil
	end)
	-- One edge of the ring: its quarter of `left`, in order top, right, bottom, left.
	local EDGE = 5
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
				return if horizontal then UDim2.new(fill:get(), 0, 0, EDGE) else UDim2.new(0, EDGE, fill:get(), 0)
			end),
		})
	end
	return New("Frame")({
		Name = "Water",
		-- Right above Shop on desktop; on touch screens beside it (mid-right), clear of the jump
		-- button below and the right column above.
		AnchorPoint = Computed(function()
			return if State.touch:get() then Vector2.new(1, 0.5) else Vector2.new(1, 1)
		end),
		Position = Computed(function()
			return if State.touch:get() then UDim2.new(1, -176, 0.5, 0) else UDim2.new(1, -14, 1, -92)
		end),
		Size = UDim2.fromOffset(86, 86),
		BackgroundTransparency = 1,
		Visible = atPlot,
		[Children] = {
			C.button({
				Size = UDim2.fromScale(1, 1),
				Color = NAVY,
				Text = "",
				Disabled = watering,
				Pulse = Computed(function()
					return not watering:get() and growing:get()
				end),
				Selected = Computed(function()
					return State.objective:get().ui == "Water"
				end),
				OnClick = function()
					Remotes.get("Water"):FireServer()
				end,
				Children = {
					C.label({
						Text = "💧",
						Position = UDim2.fromOffset(0, 8),
						Size = UDim2.new(1, 0, 0, 36),
						MaxTextSize = 30,
						ZIndex = 4,
					}),
					C.label({
						Text = Computed(function()
							local snap = State.snapshot:get()
							if watering:get() and snap then
								return "2x " .. clock(snap.wateredUntil - State.now:get())
							end
							return "WATER"
						end),
						Position = UDim2.fromOffset(4, 48),
						Size = UDim2.new(1, -8, 0, 20),
						MaxTextSize = 16,
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
			return UDim2.new(0.5, trayShift:get(), 1, -190)
		end),
		Size = UDim2.fromOffset(400, 32),
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = Computed(function()
			local o = objective:get()
			return o.text ~= "" and (atPlot:get() or o.hub == true)
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

-- Bag count, bottom-left, plot only (its worth floats over the Sell pad in the hub).
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
		LayoutOrder = 3,
		Size = UDim2.fromOffset(130, 44),
		BackgroundTransparency = 1,
		Visible = atPlot,
		[Children] = C.pill({
			Size = UDim2.fromScale(1, 1),
			Rim = Computed(function()
				local c = count:get()
				return if c.cap > 0 and c.n >= c.cap * 0.9 then Theme.colors.danger else NAVY
			end),
			Children = C.label({
				Position = UDim2.fromOffset(12, 7),
				Size = UDim2.new(1, -20, 1, -14),
				MaxTextSize = 20,
				ZIndex = 2,
				Text = Computed(function()
					local c = count:get()
					return string.format("🎒 %d/%d", c.n, c.cap)
				end),
			}),
		}),
	})
end

-- Right column under the Daily/Almanac icons: weather (hub), Starter Bundle (always, while it
-- runs), bag count (plot). Kept off the left side, which belongs to Roblox's buttons and chat.
local function rightColumn()
	return New("Frame")({
		Name = "RightColumn",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 74),
		Size = UDim2.fromOffset(250, 200),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 10),
			}),
			weatherText(),
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
		gemsBox(),
		dailyButton(),
		almanacButton(),
		shopButton(),
		-- hub
		rightColumn(),
		-- plot
		eggTray(),
		waterButton(),
		nextUp(),
	}
end
