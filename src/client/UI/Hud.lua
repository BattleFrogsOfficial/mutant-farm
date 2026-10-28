--!strict
-- Always-on HUD, laid out in fixed zones on the 900x540 design canvas so nothing can overlap:
--   top strip     Cash (rolling counter + payout bar with $/min), Gems (green + opens the Store),
--                 Bag (count + what it's worth), at the very top of the screen (the ScreenGui ignores
--                 the top-bar inset; Roblox's own buttons are top-left)
--   top right     Rebirth progress, next weather event, Starter Bundle countdown (new players)
--   left edge     Daily, Almanac and Codes tiles, vertically centered (badges, alerts, pulses)
--   bottom left   NEXT UP quest card with progress
--   bottom center egg tray: your eggs, the next locked tier, and the 2x Luck badge
--   bottom right  SHOP, HATCH (or "NEXT IN 1:42"), WATER
-- Toasts: good news under the top strip, neutral hints above the egg tray (Toasts.lua).

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
local Valuation = require(Shared.Valuation)
local State = require(script.Parent.Parent.State)
local Purchase = require(script.Parent.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, ForPairs, Observer, Spring, OnEvent =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs, Fusion.Observer, Fusion.Spring, Fusion.OnEvent

local GEM = Color3.fromHex("#4FD8FF")
local SHOP_PINK = Color3.fromHex("#FF4FA3")

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

-- Invisible full-size button on top of a box, for HUD readouts you can tap.
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

-- Square icon badge at the left end of a stat box.
local function iconBadge(icon: string, color: any, size: number?)
	local s = size or 42
	return New("Frame")({
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 13, 0.5, 0),
		Size = UDim2.fromOffset(s, s),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		[Children] = {
			C.stroke(Theme.colors.ink, 3),
			C.bevel(3, 0.55),
			C.label({ Text = icon, Size = UDim2.fromScale(1, 1), MaxTextSize = 26, ZIndex = 3 }),
		},
	})
end

-- Dark bar with a fill and a label on top, used under every top-strip number.
local function bar(props: { fill: any, color: any, text: any, position: UDim2?, size: UDim2? })
	return New("Frame")({
		Name = "Bar",
		Position = props.position or UDim2.new(0, 66, 1, -25),
		Size = props.size or UDim2.new(1, -78, 0, 18),
		BackgroundColor3 = Theme.colors.ink,
		BorderSizePixel = 0,
		ZIndex = 2,
		[Children] = {
			New("Frame")({
				Name = "Fill",
				BorderSizePixel = 0,
				BackgroundColor3 = props.color,
				Size = Computed(function()
					return UDim2.fromScale(math.clamp(C.read(props.fill), 0, 1), 1)
				end),
				ZIndex = 3,
			}),
			C.label({
				Name = "Text",
				Text = props.text,
				Size = UDim2.new(1, -10, 1, -4),
				Position = UDim2.fromOffset(5, 2),
				MaxTextSize = 13,
				StrokeThickness = 1.5,
				ZIndex = 4,
			}),
		},
	})
end

---------------------------------------------------------------------------- top strip

-- 0..1 progress toward the next pen payout, smooth (driven by the UI clock).
local payoutProgress = Computed(function()
	State.clock:get()
	local snap = State.snapshot:get()
	if not snap or not snap.nextPayoutAt or snap.nextPayoutAt <= 0 then
		return 0
	end
	local left = snap.nextPayoutAt - workspace:GetServerTimeNow()
	return math.clamp(1 - left / (snap.payoutSeconds or 60), 0, 1)
end)
local payoutFlash = Computed(function()
	return State.clock:get() - State.lastPayout:get().at < 0.7
end)
local income = Computed(function()
	local snap = State.snapshot:get()
	return if snap then snap.incomePerMinute or 0 else 0
end)

-- Cash: the balance rolls instead of jumping; the payout bar fills toward the next pen payout and
-- reads "+$X / MIN · 0:21". "+$" pops drop out underneath whenever Cash goes up.
local function cashBox()
	local rolling = Spring(State.cash, 12, 1)
	-- Don't count up from $0 on join: jump straight to the first real balance.
	local snapped = false
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
		Position = UDim2.new(0.5, -163, 0, 8),
		Size = UDim2.fromOffset(250, 66),
		Rim = Theme.colors.gold,
		Children = {
			New("UIScale")({
				Scale = Computed(function()
					return 1 + bumpSpring:get() * 0.06
				end),
			}),
			New("Frame")({
				Name = "Coin",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 13, 0.5, 0),
				Size = UDim2.fromOffset(42, 42),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 2,
				[Children] = {
					C.stroke(Theme.colors.ink, 3),
					C.gradient(Color3.fromHex("#FFE58A"), Theme.colors.gold),
					C.bevel(3, 0.45),
					C.label({
						Text = "$",
						Size = UDim2.fromScale(1, 1),
						MaxTextSize = 30,
						TextColor3 = Color3.fromHex("#8A5A12"),
						StrokeThickness = 0,
						ZIndex = 3,
					}),
				},
			}),
			C.label({
				Name = "Amount",
				Size = UDim2.new(1, -78, 0, 32),
				Position = UDim2.fromOffset(66, 5),
				TextColor3 = Theme.colors.toxic,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 30,
				StrokeThickness = 3,
				ZIndex = 2,
				Text = Computed(function()
					return Format.cash(math.floor(rolling:get() + 0.5))
				end),
			}),
			bar({
				fill = Computed(function()
					return if income:get() > 0 then payoutProgress:get() else 0
				end),
				color = Computed(function()
					return if payoutFlash:get() then Theme.colors.gold else Theme.colors.toxicDark
				end),
				text = Computed(function()
					if income:get() <= 0 then
						return "HATCH TO EARN / MIN"
					end
					State.now:get() -- tick the countdown
					local snap = State.snapshot:get(false)
					local left = if snap then math.max(0, snap.nextPayoutAt - workspace:GetServerTimeNow()) else 0
					return string.format("+%s / MIN  ·  %s", Format.cash(income:get()), clock(left))
				end),
			}),
		},
	})

	-- "+$1.2K" pops out under the box whenever Cash goes up. Skip the first snapshot.
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
		-- Pen payouts get a paw so players learn where that money came from.
		local payout = State.lastPayout:get(false)
		local fromPen = payout.amount == gained and State.clock:get(false) - payout.at < 1.5
		local pop = C.label({
			Text = "+" .. Format.cash(gained) .. (if fromPen then " 🐾" else ""),
			TextColor3 = Theme.colors.gold,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 20),
			Size = UDim2.fromOffset(220, 34),
			MaxTextSize = 28,
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
			Position = UDim2.new(0.5, 0, 1, 64),
			TextTransparency = 1,
		}):Play()
		task.delay(1.2, function()
			pop:Destroy()
		end)
	end)
	return box
end

-- Gems with the universal green "+" (opens the Store).
local function gemsBox()
	return C.pill({
		Name = "Gems",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 40, 0, 8),
		Size = UDim2.fromOffset(140, 66),
		Rim = GEM,
		Children = {
			iconBadge("💎", GEM, 34),
			C.label({
				Name = "Amount",
				Size = UDim2.new(1, -96, 0, 30),
				Position = UDim2.fromOffset(56, 6),
				TextColor3 = GEM,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				StrokeThickness = 2.5,
				ZIndex = 2,
				Text = Computed(function()
					return Format.number(State.gems:get())
				end),
			}),
			C.label({
				Text = "GEMS",
				Size = UDim2.new(1, -96, 0, 16),
				Position = UDim2.fromOffset(56, 38),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.muted,
				MaxTextSize = 13,
				StrokeThickness = 0,
				ZIndex = 2,
			}),
			C.button({
				Name = "Plus",
				Text = "+",
				Color = Theme.colors.toxicDark,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(34, 40),
				MaxTextSize = 28,
				Pulse = Computed(function()
					return State.gems:get() == 0
				end),
				ZIndex = 4,
				OnClick = function()
					openPanel("store")
				end,
			}),
		},
	})
end

-- Bag: how full it is and what it's all worth at the Sell Pad right now.
local function bagBox()
	local count = Computed(function()
		local snap = State.snapshot:get()
		if not snap then
			return { n = 0, cap = 1, value = 0 }
		end
		local n, value = 0, 0
		for _, item in snap.inventory do
			n += 1
			value += Valuation.sellValue(item, snap.cashMultiplier)
		end
		return { n = n, cap = snap.inventoryCap, value = value }
	end)
	local fill = Computed(function()
		local c = count:get()
		return c.n / math.max(c.cap, 1)
	end)
	local accent = Computed(function()
		return if fill:get() >= 0.9 then Theme.colors.danger else Theme.colors.purple
	end)
	return C.pill({
		Name = "Bag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 203, 0, 8),
		Size = UDim2.fromOffset(170, 66),
		Rim = accent,
		Children = {
			iconBadge("🎒", accent),
			C.label({
				Size = UDim2.new(1, -78, 0, 30),
				Position = UDim2.fromOffset(66, 6),
				MaxTextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 2,
				Text = Computed(function()
					local c = count:get()
					return string.format("%d/%d", c.n, c.cap)
				end),
			}),
			bar({
				fill = fill,
				color = accent,
				text = Computed(function()
					local c = count:get()
					return if c.n > 0 then "WORTH " .. Format.cash(c.value) else "EMPTY"
				end),
			}),
		},
	})
end

---------------------------------------------------------------------------- top right

local function rebirthBox()
	local progress = Computed(function()
		local snap = State.snapshot:get()
		if not snap or not snap.rebirthCost then
			return 0
		end
		return math.clamp(snap.cash / snap.rebirthCost, 0, 1)
	end)
	local ready = Computed(function()
		return progress:get() >= 1
	end)
	return C.pill({
		Name = "Rebirth",
		Size = UDim2.fromOffset(150, 50),
		Rim = Theme.colors.purple,
		Children = {
			C.pulse(ready, 0.05),
			C.label({
				Text = Computed(function()
					local snap = State.snapshot:get()
					return "♻ REBIRTH " .. ((if snap then snap.rebirths else 0) + 1)
				end),
				Position = UDim2.fromOffset(12, 5),
				Size = UDim2.new(1, -20, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
				ZIndex = 2,
			}),
			bar({
				fill = progress,
				color = Computed(function()
					return if ready:get() then Theme.colors.gold else Theme.colors.purple
				end),
				text = Computed(function()
					return if ready:get() then "READY!" else string.format("%d%%", math.floor(progress:get() * 100))
				end),
				position = UDim2.new(0, 12, 1, -22),
				size = UDim2.new(1, -22, 0, 15),
			}),
			hit(function()
				openPanel("rebirth")
			end),
		},
	})
end

-- "☢ ACID RAIN IN 4:12", or while it runs "☢ ACID RAIN · 1:12 LEFT" in the event's color.
local function weatherLine()
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
	return New("Frame")({
		Name = "Weather",
		Size = UDim2.fromOffset(150, 30),
		BorderSizePixel = 0,
		BackgroundColor3 = Computed(function()
			local i = info:get()
			return if i and i.active
				then Color3.fromHex(i.event.color):Lerp(Theme.colors.ink, 0.35)
				else Theme.colors.panel
		end),
		Visible = Computed(function()
			return info:get() ~= nil
		end),
		[Children] = {
			C.stroke(Theme.colors.ink, 3),
			C.pulse(
				Computed(function()
					local i = info:get()
					return i ~= nil and i.active
				end),
				0.04
			),
			C.label({
				Size = UDim2.new(1, -12, 1, -8),
				Position = UDim2.fromOffset(6, 4),
				MaxTextSize = 13,
				StrokeThickness = 1.5,
				TextColor3 = Computed(function()
					local i = info:get()
					return if i and not i.active then Color3.fromHex(i.event.color) else Theme.colors.white
				end),
				Text = Computed(function()
					local i = info:get()
					if not i then
						return ""
					end
					local name = i.event.icon .. " " .. string.upper(i.event.name)
					return if i.active then name .. " · " .. clock(i.left) else name .. " IN " .. clock(i.left)
				end),
			}),
		},
	})
end

local function bundleRibbon()
	local left = Computed(function()
		local snap = State.snapshot:get()
		local endsAt = if snap then snap.bundleOfferEndsAt or 0 else 0
		return endsAt - State.now:get()
	end)
	return New("Frame")({
		Name = "Bundle",
		Size = UDim2.fromOffset(150, 46),
		BackgroundTransparency = 1,
		Visible = Computed(function()
			return left:get() > 0
		end),
		[Children] = C.button({
			Size = UDim2.fromScale(1, 1),
			Color = SHOP_PINK,
			Text = "",
			Pulse = true,
			OnClick = function()
				State.panel:set("store")
			end,
			Children = {
				C.label({
					Text = "🎁 STARTER BUNDLE",
					Position = UDim2.fromOffset(6, 3),
					Size = UDim2.new(1, -12, 0, 16),
					MaxTextSize = 13,
					ZIndex = 4,
				}),
				C.label({
					Text = Computed(function()
						return "ENDS IN " .. clock(left:get())
					end),
					Position = UDim2.fromOffset(6, 20),
					Size = UDim2.new(1, -12, 0, 14),
					MaxTextSize = 12,
					TextColor3 = Color3.fromHex("#FFF3A8"),
					ZIndex = 4,
				}),
			},
		}),
	})
end

local function topRight()
	return New("Frame")({
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(150, 160),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 10),
			}),
			rebirthBox(),
			weatherLine(),
			bundleRibbon(),
		},
	})
end

---------------------------------------------------------------------------- left column

local function sideMenu()
	local dailyReady = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and snap.daily ~= nil and snap.daily.canClaim
	end)
	local almanacNew = Computed(function()
		local seen = State.almanacSeen:get()
		return seen >= 0 and almanacCount:get() > seen
	end)
	local function selected(name: string)
		return Computed(function()
			return State.panel:get() == name
		end)
	end
	return New("Frame")({
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, -24),
		Size = UDim2.fromOffset(150, 300),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				Padding = UDim.new(0, 22),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			C.tile({
				Name = "Daily",
				Icon = "🎁",
				Label = "DAILY",
				Color = Theme.colors.danger,
				LayoutOrder = 1,
				Alert = dailyReady,
				Badge = Computed(function()
					local snap = State.snapshot:get()
					local streak = if snap and snap.daily then snap.daily.streak else 0
					return if streak > 0
						then "🔥 " .. streak .. (if streak == 1 then " DAY" else " DAYS")
						else "CLAIM!"
				end),
				Selected = selected("daily"),
				OnClick = function()
					openPanel("daily")
				end,
			}),
			C.tile({
				Name = "Almanac",
				Icon = "📖",
				Label = "ALMANAC",
				Color = Theme.colors.purple,
				LayoutOrder = 2,
				Alert = almanacNew,
				Badge = Computed(function()
					return string.format("%d/%d", almanacCount:get(), TOTAL_SPECIES)
				end),
				Selected = selected("almanac"),
				OnClick = function()
					State.almanacSeen:set(almanacCount:get(false))
					openPanel("almanac")
				end,
			}),
			C.tile({
				Name = "Codes",
				Icon = "🐦",
				Label = "CODES",
				Color = Theme.colors.water,
				LayoutOrder = 3,
				Badge = "FREE STUFF",
				Selected = selected("codes"),
				OnClick = function()
					openPanel("codes")
				end,
			}),
		},
	})
end

---------------------------------------------------------------------------- bottom

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
		Size = UDim2.fromOffset(88, 100),
		BackgroundTransparency = 1,
		[Children] = New("Frame")({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = Computed(function()
				return UDim2.fromOffset(0, lift:get())
			end),
			[Children] = C.button({
				Size = UDim2.fromScale(1, 1),
				Color = Color3.fromHex(tier.color):Lerp(Theme.colors.slateLight, 0.5),
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
		Size = UDim2.fromOffset(88, 100),
		BackgroundTransparency = 1,
		Visible = Computed(function()
			return nextTier:get() ~= nil
		end),
		[Children] = C.button({
			Size = UDim2.fromScale(1, 1),
			Color = Theme.colors.locked,
			Text = "",
			OnClick = function()
				State.panel:set("rebirth")
			end,
			Children = {
				C.padlock({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.fromOffset(30, 36),
					ZIndex = 4,
				}),
				C.label({
					Text = Computed(function()
						local id = nextTier:get()
						return if id then string.upper((Eggs.tiers[id].name:gsub(" Egg", ""))) else ""
					end),
					Position = UDim2.new(0, 4, 0, 48),
					Size = UDim2.new(1, -8, 0, 18),
					MaxTextSize = 15,
					TextColor3 = Theme.colors.cream,
					ZIndex = 4,
				}),
				C.label({
					Text = Computed(function()
						local id = nextTier:get()
						return if id then "REBIRTH " .. Eggs.tiers[id].unlockRebirth else ""
					end),
					Position = UDim2.new(0, 4, 0, 68),
					Size = UDim2.new(1, -8, 0, 14),
					MaxTextSize = 12,
					TextColor3 = Theme.colors.gold,
					ZIndex = 4,
				}),
			},
		}),
	})
end

-- 2x Luck pass badge on the tray: the pass sells from the hatch moment, not from a menu.
local function luckBadge()
	local owned = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and snap.ownedPasses ~= nil and snap.ownedPasses.Luck2x == true
	end)
	return New("TextButton")({
		Name = "LuckBadge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.fromOffset(98, 26),
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		BackgroundColor3 = Computed(function()
			return if owned:get() then Theme.colors.toxicDark else Theme.colors.gold
		end),
		ZIndex = 3,
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
					return if owned:get() then "✓ 2x LUCK" else "🔒 2x LUCK"
				end),
				Size = UDim2.new(1, -8, 1, -6),
				Position = UDim2.fromOffset(4, 3),
				MaxTextSize = 14,
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
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(420, 136),
		BackgroundTransparency = 1,
		[Children] = {
			C.shadow(),
			New("Frame")({
				Name = "Tray",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.08,
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
				BackgroundColor3 = Theme.colors.toxicDark,
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
				Position = UDim2.fromOffset(10, 22),
				Size = UDim2.new(1, -20, 1, -28),
				ScrollBarThickness = 4,
				ScrollingDirection = Enum.ScrollingDirection.X,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				ZIndex = 2,
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 10),
					}),
					ForPairs(eggs, function(eggId: string, count: number)
						return eggId, eggCard(eggId, count)
					end, Fusion.cleanup),
					lockedCard(),
				},
			}),
			C.label({
				Name = "Empty",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 8),
				Size = UDim2.new(1, -140, 0, 60),
				MaxTextSize = 18,
				TextColor3 = Theme.colors.cream,
				TextXAlignment = Enum.TextXAlignment.Left,
				Visible = Computed(function()
					return not hasEggs:get()
				end),
				Text = "BUY EGGS AT THE\nEGG SHOP PAD 🥚",
				ZIndex = 3,
			}),
		},
	})
end

local function actionButtons()
	local watering = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and State.now:get() < snap.wateredUntil
	end)
	local waterLeft = Computed(function()
		local snap = State.snapshot:get()
		if not snap then
			return 0
		end
		return math.clamp((snap.wateredUntil - State.now:get()) / 30, 0, 1)
	end)
	local ready = Computed(function()
		return State.readyCount:get() > 0
	end)
	local growing = Computed(function()
		return State.nextReadyIn:get() ~= nil
	end)
	return New("Frame")({
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -12),
		Size = UDim2.fromOffset(186, 220),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 12),
			}),
			C.button({
				Name = "Shop",
				LayoutOrder = 0,
				Size = UDim2.fromOffset(186, 54),
				Color = SHOP_PINK,
				Icon = "🛒",
				Text = "SHOP",
				MaxTextSize = 24,
				OnClick = function()
					openPanel("store")
				end,
			}),
			C.button({
				Name = "Hatch",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(186, 66),
				Color = Theme.colors.gold,
				Icon = Computed(function()
					return if ready:get() then "🥚" else ""
				end),
				MaxTextSize = 26,
				Pulse = ready,
				Selected = ready,
				Disabled = Computed(function()
					return not ready:get()
				end),
				Text = Computed(function()
					local n = State.readyCount:get()
					if n > 0 then
						return string.format("HATCH %d", n)
					end
					local left = State.nextReadyIn:get()
					return if left then "NEXT IN " .. clock(left) else "PLANT EGGS"
				end),
				OnClick = function()
					Remotes.get("HarvestAll"):FireServer()
				end,
			}),
			C.button({
				Name = "Water",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(186, 60),
				Color = Theme.colors.water,
				Icon = "💧",
				Text = "WATER",
				MaxTextSize = 24,
				Disabled = watering,
				-- Ready, and there's something growing that it would speed up.
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
						-- While it runs: what it's doing and how long is left.
						Name = "Active",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -6, 0, 3),
						Size = UDim2.fromOffset(70, 16),
						MaxTextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Right,
						TextColor3 = Color3.fromHex("#BFF0FF"),
						Visible = watering,
						ZIndex = 5,
						Text = Computed(function()
							local snap = State.snapshot:get()
							return if snap then "2x · " .. clock(snap.wateredUntil - State.now:get()) else ""
						end),
					}),
					New("Frame")({
						-- Drains while the 2x speed lasts.
						Name = "Drain",
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 8, 1, -5),
						Size = Computed(function()
							return UDim2.new(waterLeft:get(), -16 * waterLeft:get(), 0, 5)
						end),
						BackgroundColor3 = Theme.colors.white,
						BorderSizePixel = 0,
						Visible = watering,
						ZIndex = 4,
					}),
				},
			}),
		},
	})
end

-- Bottom-left: the current goal, with a progress bar when there's a number to reach.
local function nextUp()
	local objective = State.objective
	local progress = Spring(
		Computed(function()
			return objective:get().progress or 0
		end),
		18,
		1
	)
	return New("Frame")({
		Name = "NextUp",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.fromOffset(222, 104),
		BackgroundTransparency = 1,
		Visible = Computed(function()
			return objective:get().text ~= ""
		end),
		[Children] = {
			C.shadow(),
			New("Frame")({
				Name = "Card",
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
				Name = "Stripe",
				Size = UDim2.new(0, 5, 1, 0),
				BackgroundColor3 = Theme.colors.toxic,
				BorderSizePixel = 0,
				ZIndex = 2,
			}),
			New("Frame")({
				Name = "Tag",
				Position = UDim2.fromOffset(12, -12),
				Size = UDim2.fromOffset(104, 24),
				BackgroundColor3 = Theme.colors.toxic,
				BorderSizePixel = 0,
				ZIndex = 3,
				[Children] = {
					C.stroke(Theme.colors.ink, 2.5),
					C.label({
						Text = "⭐ NEXT UP",
						Size = UDim2.new(1, -10, 1, -6),
						Position = UDim2.fromOffset(5, 3),
						MaxTextSize = 14,
						ZIndex = 4,
					}),
				},
			}),
			C.label({
				Text = Computed(function()
					return objective:get().text
				end),
				Position = UDim2.fromOffset(16, 20),
				Size = UDim2.new(1, -28, 0, 50),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				MaxTextSize = 18,
				ZIndex = 2,
			}),
			New("Frame")({
				Name = "Bar",
				Position = UDim2.new(0, 16, 1, -24),
				Size = UDim2.new(1, -30, 0, 14),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				Visible = Computed(function()
					return objective:get().progress ~= nil
				end),
				ZIndex = 2,
				[Children] = New("Frame")({
					BackgroundColor3 = Theme.colors.toxicDark,
					BorderSizePixel = 0,
					Size = Computed(function()
						return UDim2.fromScale(math.clamp(progress:get(), 0.04, 1), 1)
					end),
					ZIndex = 3,
				}),
			}),
		},
	})
end

return function()
	return {
		cashBox(),
		gemsBox(),
		bagBox(),
		topRight(),
		sideMenu(),
		eggTray(),
		actionButtons(),
		nextUp(),
	}
end
