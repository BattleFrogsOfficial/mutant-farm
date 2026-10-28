--!strict
-- Always-on HUD, laid out in fixed zones on the 900x540 design canvas so nothing can overlap:
--   top center    Cash pill (rolling counter) + income chip, Bag pill
--   left column   Daily reward tile, Almanac tile (badges, alert dots, pulses)
--   bottom left   NEXT UP quest card with progress
--   bottom center egg tray with live 3D eggs
--   bottom right  HATCH (pulses when eggs are ready) and WATER (drain bar)
-- Toasts live under the top bar (Toasts.lua); the hatch cinematic is its own screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local MutantModel = require(Shared.MutantModel)
local Mutants = require(Shared.Config.Mutants)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Viewport = require(script.Parent.Viewport)

local New, Children, Computed, ForPairs, Observer, Spring =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs, Fusion.Observer, Fusion.Spring

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

---------------------------------------------------------------------------- top

local function coin(size: number)
	return New("Frame")({
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		[Children] = {
			C.round(),
			C.stroke(Theme.colors.goldDark, 3),
			C.gradient(Color3.fromHex("#FFE58A"), Theme.colors.gold),
			C.label({
				Text = "$",
				Size = UDim2.fromScale(1, 1),
				MaxTextSize = 28,
				TextColor3 = Theme.colors.goldDark,
				StrokeThickness = 0,
				ZIndex = 3,
			}),
		},
	})
end

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

local function cashPill()
	-- The number rolls up/down instead of jumping, and the pill bumps when it goes up.
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
	local pill = C.pill({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -72, 0, 8),
		Size = UDim2.fromOffset(268, 58),
		Rim = Theme.colors.toxic,
		Children = {
			New("UIScale")({
				Scale = Computed(function()
					return 1 + bumpSpring:get() * 0.08
				end),
			}),
			coin(44),
			C.label({
				Size = UDim2.new(1, -70, 1, -20),
				Position = UDim2.fromOffset(58, 5),
				TextColor3 = Theme.colors.toxic,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 36,
				StrokeThickness = 3,
				ZIndex = 2,
				Text = Computed(function()
					return Format.cash(math.floor(rolling:get() + 0.5))
				end),
			}),
			-- Fills up toward the next pen payout, flashes gold when it pays.
			New("Frame")({
				Name = "PayoutBar",
				Position = UDim2.new(0, 58, 1, -14),
				Size = UDim2.new(1, -76, 0, 8),
				BackgroundColor3 = Theme.colors.slate,
				Visible = Computed(function()
					local snap = State.snapshot:get()
					return snap ~= nil and (snap.incomePerMinute or 0) > 0
				end),
				ZIndex = 2,
				[Children] = {
					C.round(),
					New("Frame")({
						Name = "Fill",
						BackgroundColor3 = Color3.new(1, 1, 1),
						Size = Computed(function()
							return UDim2.fromScale(math.max(payoutProgress:get(), 0.03), 1)
						end),
						ZIndex = 3,
						[Children] = {
							C.round(),
							New("UIGradient")({
								Rotation = 90,
								Color = Computed(function()
									if payoutFlash:get() then
										return ColorSequence.new(Color3.fromHex("#FFF3A8"), Theme.colors.gold)
									end
									return ColorSequence.new(Color3.fromHex("#B8FF8A"), Theme.colors.toxicDark)
								end),
							}),
						},
					}),
				},
			}),
		},
	})

	-- "+$1.2K" pops out under the pill whenever Cash goes up. Skip the first snapshot.
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
			Position = UDim2.new(0.5, 0, 1, 18),
			Size = UDim2.fromOffset(220, 38),
			MaxTextSize = 32,
			StrokeThickness = 3,
			ZIndex = 8,
		})
		local scale = Instance.new("UIScale")
		scale.Scale = 0.3
		scale.Parent = pop
		pop.Parent = pill
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
	return pill
end

local function incomeChip()
	local income = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.incomePerMinute or 0 else 0
	end)
	return New("Frame")({
		Name = "Income",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -72, 0, 70),
		Size = UDim2.fromOffset(236, 26),
		BackgroundColor3 = Theme.colors.slate,
		BackgroundTransparency = 0.15,
		Visible = Computed(function()
			return State.snapshot:get() ~= nil
		end),
		[Children] = {
			C.round(),
			C.label({
				Size = UDim2.new(1, -16, 1, -4),
				Position = UDim2.fromOffset(8, 2),
				TextColor3 = Computed(function()
					return if income:get() > 0 then Theme.colors.toxic else Theme.colors.cream
				end),
				MaxTextSize = 18,
				Text = Computed(function()
					if income:get() <= 0 then
						return "🐾 Keep mutants to earn per minute"
					end
					State.now:get() -- tick the countdown
					local snap = State.snapshot:get(false)
					local left = if snap then math.max(0, snap.nextPayoutAt - workspace:GetServerTimeNow()) else 0
					return string.format("🐾 %s / min  ·  %s", Format.cash(income:get()), Format.duration(left))
				end),
			}),
		},
	})
end

local function bagPill()
	local fill = Computed(function()
		local snap = State.snapshot:get()
		if not snap then
			return 0
		end
		local n = 0
		for _ in snap.inventory do
			n += 1
		end
		return n / snap.inventoryCap
	end)
	return C.pill({
		Name = "Bag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 148, 0, 12),
		Size = UDim2.fromOffset(150, 50),
		Rim = Computed(function()
			return if fill:get() >= 0.9 then Theme.colors.danger else Theme.colors.purple
		end),
		Children = {
			C.label({
				Text = "🎒",
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(0, 8, 0.5, -17),
				MaxTextSize = 26,
				ZIndex = 2,
			}),
			C.label({
				Size = UDim2.new(1, -54, 0, 26),
				Position = UDim2.fromOffset(46, 6),
				MaxTextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 2,
				Text = Computed(function()
					local snap = State.snapshot:get()
					if not snap then
						return ""
					end
					local n = 0
					for _ in snap.inventory do
						n += 1
					end
					return string.format("%d/%d", n, snap.inventoryCap)
				end),
			}),
			New("Frame")({
				Name = "Fill",
				Position = UDim2.new(0, 46, 1, -14),
				Size = UDim2.new(1, -60, 0, 6),
				BackgroundColor3 = Theme.colors.slate,
				ZIndex = 2,
				[Children] = {
					C.round(),
					New("Frame")({
						Size = Computed(function()
							return UDim2.fromScale(math.clamp(fill:get(), 0, 1), 1)
						end),
						BackgroundColor3 = Computed(function()
							return if fill:get() >= 0.9 then Theme.colors.danger else Theme.colors.purple
						end),
						ZIndex = 3,
						[Children] = C.round(),
					}),
				},
			}),
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
	return New("Frame")({
		Name = "Menu",
		Position = UDim2.fromOffset(14, 104),
		Size = UDim2.fromOffset(92, 220),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({ Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }),
			C.tile({
				Name = "Daily",
				Icon = "🎁",
				Label = "Daily",
				Color = Theme.colors.danger,
				LayoutOrder = 1,
				Alert = dailyReady,
				Badge = Computed(function()
					local snap = State.snapshot:get()
					local streak = if snap and snap.daily then snap.daily.streak else 0
					return if streak > 0
						then "🔥 " .. streak .. " day" .. (if streak == 1 then "" else "s")
						else "Claim!"
				end),
				Selected = Computed(function()
					return State.panel:get() == "daily"
				end),
				OnClick = function()
					State.panel:set(if State.panel:get(false) == "daily" then "none" else "daily")
				end,
			}),
			C.tile({
				Name = "Almanac",
				Icon = "📖",
				Label = "Almanac",
				Color = Theme.colors.purple,
				LayoutOrder = 2,
				Alert = almanacNew,
				Badge = Computed(function()
					return string.format("%d/%d", almanacCount:get(), TOTAL_SPECIES)
				end),
				Selected = Computed(function()
					return State.panel:get() == "almanac"
				end),
				OnClick = function()
					State.almanacSeen:set(almanacCount:get(false))
					State.panel:set(if State.panel:get(false) == "almanac" then "none" else "almanac")
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
						Size = UDim2.new(1, -10, 1, -30),
						Position = UDim2.fromOffset(5, 3),
						ZIndex = 4,
					}),
					C.label({
						Text = (tier.name:gsub(" Egg", "")),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -5),
						Size = UDim2.new(1, -8, 0, 20),
						MaxTextSize = 17,
						ZIndex = 4,
					}),
					New("Frame")({
						Name = "Count",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -3, 0, 3),
						Size = UDim2.fromOffset(36, 22),
						BackgroundColor3 = Theme.colors.slate,
						ZIndex = 5,
						[Children] = {
							C.round(),
							C.label({ Text = "x" .. count, Size = UDim2.fromScale(1, 1), MaxTextSize = 16, ZIndex = 6 }),
						},
					}),
				},
			}),
		}),
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
			C.shadow(22, 5),
			New("Frame")({
				Name = "Tray",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.12,
				ZIndex = 1,
				[Children] = {
					C.corner(22),
					C.stroke(Theme.colors.slate, 3),
					C.gradient(Theme.colors.slateLight, Theme.colors.slate),
				},
			}),
			New("Frame")({
				Name = "Tab",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(220, 26),
				BackgroundColor3 = Theme.colors.toxicDark,
				ZIndex = 3,
				[Children] = {
					C.round(),
					C.stroke(Theme.colors.slate, 2.5),
					C.label({
						Size = UDim2.new(1, -16, 1, -4),
						Position = UDim2.fromOffset(8, 2),
						MaxTextSize = 17,
						ZIndex = 4,
						Text = Computed(function()
							return if hasEggs:get() then "PICK AN EGG · TAP SOIL" else "OUT OF EGGS"
						end),
					}),
				},
			}),
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
				Visible = hasEggs,
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
				},
			}),
			C.label({
				Name = "Empty",
				Position = UDim2.fromOffset(20, 30),
				Size = UDim2.new(1, -40, 1, -44),
				MaxTextSize = 24,
				TextColor3 = Theme.colors.cream,
				Visible = Computed(function()
					return not hasEggs:get()
				end),
				Text = "Buy eggs at the EGG SHOP\nin the middle of the map 🥚",
				ZIndex = 2,
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
	return New("Frame")({
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -12),
		Size = UDim2.fromOffset(186, 150),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 14),
			}),
			C.button({
				Name = "Hatch",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(186, 66),
				Color = Theme.colors.gold,
				Icon = "🥚",
				MaxTextSize = 28,
				Pulse = ready,
				Selected = ready,
				Disabled = Computed(function()
					return not ready:get()
				end),
				Text = Computed(function()
					local n = State.readyCount:get()
					return if n > 0 then string.format("HATCH %d", n) else "HATCH"
				end),
				OnClick = function()
					Remotes.get("HarvestAll"):FireServer()
				end,
			}),
			C.button({
				Name = "Water",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(186, 66),
				Color = Theme.colors.water,
				Icon = "💧",
				MaxTextSize = 26,
				Disabled = watering,
				Pulse = Computed(function()
					return State.objective:get().ui == "Water"
				end),
				Selected = Computed(function()
					return State.objective:get().ui == "Water"
				end),
				Text = Computed(function()
					local snap = State.snapshot:get()
					if snap and watering:get() then
						return "2x " .. Format.duration(snap.wateredUntil - State.now:get())
					end
					return "WATER"
				end),
				OnClick = function()
					Remotes.get("Water"):FireServer()
				end,
				Children = New("Frame")({
					-- Drains while the 2x speed lasts.
					Name = "Drain",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 10, 1, -6),
					Size = Computed(function()
						return UDim2.new(waterLeft:get(), -20 * waterLeft:get(), 0, 6)
					end),
					BackgroundColor3 = Theme.colors.white,
					BackgroundTransparency = 0.25,
					Visible = watering,
					ZIndex = 4,
					[Children] = C.round(),
				}),
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
			C.shadow(18, 5),
			New("Frame")({
				Name = "Card",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 1,
				[Children] = {
					C.corner(18),
					C.stroke(Theme.colors.toxic, 3),
					C.gradient(Theme.colors.slateLight, Theme.colors.slate),
				},
			}),
			New("Frame")({
				Name = "Tag",
				Position = UDim2.fromOffset(12, -12),
				Size = UDim2.fromOffset(104, 26),
				BackgroundColor3 = Theme.colors.toxic,
				ZIndex = 3,
				[Children] = {
					C.round(),
					C.stroke(Theme.colors.slate, 2.5),
					C.label({
						Text = "⭐ NEXT UP",
						Size = UDim2.new(1, -10, 1, -4),
						Position = UDim2.fromOffset(5, 2),
						MaxTextSize = 16,
						ZIndex = 4,
					}),
				},
			}),
			C.label({
				Text = Computed(function()
					return objective:get().text
				end),
				Position = UDim2.fromOffset(14, 20),
				Size = UDim2.new(1, -28, 0, 50),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				MaxTextSize = 20,
				ZIndex = 2,
			}),
			New("Frame")({
				Name = "Bar",
				Position = UDim2.new(0, 14, 1, -24),
				Size = UDim2.new(1, -28, 0, 14),
				BackgroundColor3 = Theme.colors.slate,
				Visible = Computed(function()
					return objective:get().progress ~= nil
				end),
				ZIndex = 2,
				[Children] = {
					C.round(),
					C.stroke(Theme.colors.slate, 2),
					New("Frame")({
						BackgroundColor3 = Color3.new(1, 1, 1),
						Size = Computed(function()
							return UDim2.fromScale(math.clamp(progress:get(), 0.04, 1), 1)
						end),
						ZIndex = 3,
						[Children] = { C.round(), C.gradient(Color3.fromHex("#B8FF8A"), Theme.colors.toxicDark) },
					}),
				},
			}),
		},
	})
end

return function()
	return { cashPill(), incomeChip(), bagPill(), sideMenu(), eggTray(), actionButtons(), nextUp() }
end
