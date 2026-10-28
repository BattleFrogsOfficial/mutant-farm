--!strict
-- Always-on HUD: Cash with a rolling counter and $/min (top), Bag (top), Almanac button (left),
-- egg hotbar with live 3D eggs (bottom), Water / Hatch buttons (bottom right), "Next up"
-- objective (bottom left), and the big hatch banner.

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

local function coin(size: number)
	return New("Frame")({
		Name = "Coin",
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = Theme.colors.gold,
		[Children] = {
			C.round(),
			C.stroke(Theme.colors.goldDark, 3),
			C.shine(),
			C.label({ Text = "$", Size = UDim2.fromScale(1, 1), MaxTextSize = 26, TextColor3 = Theme.colors.goldDark }),
		},
	})
end

local function cashPill()
	-- The number rolls up/down instead of jumping.
	local rolling = Spring(State.cash, 14, 1)
	local pill = C.pill({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -50, 0, 8),
		Size = UDim2.fromOffset(250, 56),
		Rim = Theme.colors.toxic,
		Children = {
			coin(40),
			C.label({
				Size = UDim2.new(1, -66, 1, -12),
				Position = UDim2.fromOffset(54, 6),
				TextColor3 = Theme.colors.toxic,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 36,
				StrokeThickness = 2.5,
				Text = Computed(function()
					return Format.cash(math.floor(rolling:get() + 0.5))
				end),
			}),
			C.label({
				Name = "Income",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 2),
				Size = UDim2.fromOffset(230, 22),
				TextColor3 = Theme.colors.cream,
				MaxTextSize = 18,
				Text = Computed(function()
					local snap = State.snapshot:get()
					local income = if snap then snap.incomePerMinute or 0 else 0
					return if income > 0 then "+" .. Format.cash(income) .. " / min" else ""
				end),
			}),
		},
	})
	-- "+$1.2K" pops out of the pill whenever Cash goes up. Skip the first snapshot.
	local last: number? = nil
	Observer(State.cash):onChange(function()
		local now = State.cash:get(false)
		local previous = last
		last = now
		local gained = if previous then now - previous else 0
		if gained <= 0 then
			return
		end
		local pop = C.label({
			Text = "+" .. Format.cash(gained),
			TextColor3 = Theme.colors.gold,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 34),
			Size = UDim2.fromOffset(220, 40),
			MaxTextSize = 34,
			StrokeThickness = 3,
			ZIndex = 5,
		})
		local scale = Instance.new("UIScale")
		scale.Scale = 0.4
		scale.Parent = pop
		pop.Parent = pill
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		TweenService:Create(pop, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 1, 80),
			TextTransparency = 1,
		}):Play()
		task.delay(1.3, function()
			pop:Destroy()
		end)
	end)
	return pill
end

local function bagPill()
	return C.pill({
		Name = "Bag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 150, 0, 12),
		Size = UDim2.fromOffset(130, 48),
		Rim = Theme.colors.purple,
		Children = {
			C.label({
				Text = "🎒",
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(0, 8, 0.5, -17),
				MaxTextSize = 26,
			}),
			C.label({
				Size = UDim2.new(1, -52, 1, -14),
				Position = UDim2.fromOffset(44, 7),
				MaxTextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
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
		},
	})
end

local function sideMenu()
	return New("Frame")({
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.45, 0),
		Size = UDim2.fromOffset(84, 200),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({ Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
			C.iconButton({
				Name = "Almanac",
				Icon = "📖",
				Label = "Almanac",
				Color = Theme.colors.purple,
				LayoutOrder = 1,
				Selected = Computed(function()
					return State.panel:get() == "almanac"
				end),
				OnClick = function()
					State.panel:set(if State.panel:get(false) == "almanac" then "none" else "almanac")
				end,
				Badge = Computed(function()
					local n = 0
					for _ in State.almanac:get() do
						n += 1
					end
					return string.format("%d/%d", n, TOTAL_SPECIES)
				end),
			}),
		},
	})
end

local function eggCard(eggId: string, count: number)
	local tier = Eggs.tiers[eggId]
	local selected = Computed(function()
		return State.selectedEgg:get() == eggId
	end)
	local lift = Spring(
		Computed(function()
			return if selected:get() then -10 else 0
		end),
		30,
		0.6
	)
	return New("Frame")({
		Name = eggId,
		LayoutOrder = table.find(Eggs.order, eggId),
		Size = UDim2.fromOffset(92, 104),
		BackgroundTransparency = 1,
		[Children] = New("Frame")({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = Computed(function()
				return UDim2.fromOffset(0, lift:get())
			end),
			[Children] = C.button({
				Size = UDim2.fromScale(1, 1),
				Color = Color3.fromHex(tier.color):Lerp(Theme.colors.slateLight, 0.55),
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
						Size = UDim2.new(1, -8, 1, -30),
						Position = UDim2.fromOffset(4, 2),
						ZIndex = 3,
					}),
					C.label({
						Text = (tier.name:gsub(" Egg", "")),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -4),
						Size = UDim2.new(1, -8, 0, 22),
						MaxTextSize = 18,
						ZIndex = 3,
					}),
					New("Frame")({
						Name = "Count",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -2, 0, 2),
						Size = UDim2.fromOffset(38, 24),
						BackgroundColor3 = Theme.colors.slate,
						ZIndex = 4,
						[Children] = {
							C.round(),
							C.label({ Text = "x" .. count, Size = UDim2.fromScale(1, 1), MaxTextSize = 18, ZIndex = 5 }),
						},
					}),
				},
			}),
		}),
	})
end

local function eggBar()
	local eggs = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.eggs else {}
	end)
	local hasEggs = Computed(function()
		return next(eggs:get()) ~= nil
	end)

	return New("Frame")({
		Name = "EggBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0, 560, 0, 140),
		BackgroundTransparency = 1,
		[Children] = {
			C.label({
				Size = UDim2.new(1, 0, 0, 24),
				MaxTextSize = 20,
				Text = Computed(function()
					return if hasEggs:get()
						then "Pick an egg, then tap a soil patch"
						else "Out of eggs! Visit the EGG SHOP in the middle"
				end),
			}),
			New("Frame")({
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 32),
				Size = UDim2.new(1, 0, 0, 106),
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Bottom,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 10),
					}),
					ForPairs(eggs, function(eggId: string, count: number)
						return eggId, eggCard(eggId, count)
					end, Fusion.cleanup),
				},
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
	return New("Frame")({
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -14),
		Size = UDim2.fromOffset(180, 150),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 12),
			}),
			C.button({
				Name = "Hatch",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(180, 64),
				Color = Theme.colors.gold,
				Icon = "🥚",
				Text = Computed(function()
					local n = State.readyCount:get()
					return if n > 0 then string.format("Hatch %d", n) else "Hatch"
				end),
				Selected = Computed(function()
					return State.readyCount:get() > 0
				end),
				Disabled = Computed(function()
					return State.readyCount:get() == 0
				end),
				OnClick = function()
					Remotes.get("HarvestAll"):FireServer()
				end,
			}),
			C.button({
				Name = "Water",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(180, 64),
				Color = Theme.colors.water,
				Icon = "💧",
				Disabled = watering,
				Selected = Computed(function()
					return State.objective:get().ui == "Water"
				end),
				Text = Computed(function()
					local snap = State.snapshot:get()
					if snap and watering:get() then
						return "2x " .. Format.duration(snap.wateredUntil - State.now:get())
					end
					return "Water 2x"
				end),
				OnClick = function()
					Remotes.get("Water"):FireServer()
				end,
				Children = New("Frame")({
					-- Drains while the 2x speed lasts.
					Name = "Drain",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 8, 1, -4),
					Size = Computed(function()
						return UDim2.new(waterLeft:get(), -16 * waterLeft:get(), 0, 5)
					end),
					BackgroundColor3 = Theme.colors.water,
					Visible = watering,
					ZIndex = 3,
					[Children] = C.round(),
				}),
			}),
		},
	})
end

-- Bottom-left: the current objective, with a progress bar when there's a number to reach.
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
		Position = UDim2.new(0, 12, 1, -14),
		Size = UDim2.fromOffset(260, 92),
		BackgroundColor3 = Theme.colors.slate,
		Visible = Computed(function()
			return objective:get().text ~= ""
		end),
		[Children] = {
			C.corner(18),
			C.stroke(Theme.colors.toxic, 3),
			New("Frame")({
				Name = "Tag",
				Position = UDim2.fromOffset(12, -12),
				Size = UDim2.fromOffset(96, 24),
				BackgroundColor3 = Theme.colors.toxic,
				[Children] = {
					C.round(),
					C.stroke(Theme.colors.slate, 2),
					C.label({ Text = "NEXT UP", Size = UDim2.fromScale(1, 1), MaxTextSize = 16 }),
				},
			}),
			C.label({
				Text = Computed(function()
					return objective:get().text
				end),
				Position = UDim2.fromOffset(14, 18),
				Size = UDim2.new(1, -28, 0, 44),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				MaxTextSize = 21,
			}),
			New("Frame")({
				Name = "Bar",
				Position = UDim2.new(0, 14, 1, -20),
				Size = UDim2.new(1, -28, 0, 12),
				BackgroundColor3 = Theme.colors.slateLight,
				Visible = Computed(function()
					return objective:get().progress ~= nil
				end),
				[Children] = {
					C.round(),
					New("Frame")({
						BackgroundColor3 = Theme.colors.toxic,
						Size = Computed(function()
							return UDim2.fromScale(math.clamp(progress:get(), 0, 1), 1)
						end),
						[Children] = { C.round(), C.shine() },
					}),
				},
			}),
		},
	})
end

-- Center-screen banner for Rare+ hatches.
local function banner()
	local b = State.banner
	local shown = Computed(function()
		return b:get().text ~= ""
	end)
	local scale = Spring(
		Computed(function()
			return if shown:get() then 1 else 0.3
		end),
		30,
		0.55
	)
	return C.label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(640, 130),
		MaxTextSize = 64,
		StrokeThickness = 4,
		Visible = shown,
		TextColor3 = Computed(function()
			return b:get().color
		end),
		Text = Computed(function()
			return b:get().text
		end),
		[Children] = { New("UIScale")({ Scale = scale }) },
	})
end

return function()
	return { cashPill(), bagPill(), sideMenu(), eggBar(), actionButtons(), nextUp(), banner() }
end
