--!strict
-- Always-on HUD: Cash + bag (top), egg hotbar (bottom), Water / Harvest (bottom right),
-- "Next up" objective (bottom left), and the big hatch banner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs, Observer, Spring =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs, Fusion.Observer, Fusion.Spring

local function cashPill()
	local pill = New("Frame")({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -60, 0, 8),
		Size = UDim2.fromOffset(240, 52),
		BackgroundColor3 = Theme.colors.slate,
		[Children] = {
			C.corner(26),
			C.stroke(Theme.colors.toxic, 3),
			C.label({
				Size = UDim2.new(1, -24, 1, -12),
				Position = UDim2.fromOffset(12, 6),
				TextColor3 = Theme.colors.toxic,
				MaxTextSize = 36,
				Text = Computed(function()
					return Format.cash(State.cash:get())
				end),
			}),
		},
	})
	-- "+$1.2K" floats up from the pill whenever Cash goes up.
	local last = State.cash:get(false)
	Observer(State.cash):onChange(function()
		local now = State.cash:get(false)
		local gained = now - last
		last = now
		if gained <= 0 then
			return
		end
		local pop = C.label({
			Text = "+" .. Format.cash(gained),
			TextColor3 = Theme.colors.gold,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(200, 34),
			MaxTextSize = 30,
		})
		pop.Parent = pill
		TweenService:Create(pop, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
			Position = UDim2.new(0.5, 0, 1, 50),
			TextTransparency = 1,
		}):Play()
		task.delay(1.2, function()
			pop:Destroy()
		end)
	end)
	return pill
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
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0.6, 0, 0, 96),
		BackgroundTransparency = 1,
		[Children] = {
			C.label({
				Size = UDim2.new(1, 0, 0, 24),
				MaxTextSize = 20,
				Text = Computed(function()
					return if hasEggs:get()
						then "Tap an empty plot to plant your selected egg"
						else "Out of eggs! Visit the Egg Shop in the middle"
				end),
			}),
			New("Frame")({
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 28),
				Size = UDim2.new(1, 0, 0, 64),
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					ForPairs(eggs, function(eggId: string, count: number)
						local tier = Eggs.tiers[eggId]
						return eggId,
							C.button({
								Name = eggId,
								LayoutOrder = table.find(Eggs.order, eggId),
								Size = UDim2.fromOffset(130, 60),
								Color = Color3.fromHex(tier.color),
								Text = string.format("%s x%d", eggId, count),
								OnClick = function()
									State.selectedEgg:set(eggId)
								end,
								Selected = Computed(function()
									return State.selectedEgg:get() == eggId
								end),
							})
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
	return New("Frame")({
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(170, 132),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 10),
			}),
			C.button({
				Name = "Harvest",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(170, 56),
				Color = Theme.colors.gold,
				Text = Computed(function()
					return string.format("Harvest (%d)", State.readyCount:get())
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
				Size = UDim2.fromOffset(170, 56),
				Color = Theme.colors.water,
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
			}),
		},
	})
end

local function bagCounter()
	return New("Frame")({
		Name = "Bag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 130, 0, 12),
		Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = Theme.colors.slate,
		[Children] = {
			C.corner(22),
			C.stroke(Theme.colors.purple, 3),
			C.label({
				Size = UDim2.new(1, -16, 1, -12),
				Position = UDim2.fromOffset(8, 6),
				MaxTextSize = 24,
				Text = Computed(function()
					local snap = State.snapshot:get()
					if not snap then
						return ""
					end
					local n = 0
					for _ in snap.inventory do
						n += 1
					end
					return string.format("Bag %d/%d", n, snap.inventoryCap)
				end),
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
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(250, 86),
		BackgroundColor3 = Theme.colors.slate,
		BackgroundTransparency = 0.05,
		Visible = Computed(function()
			return objective:get().text ~= ""
		end),
		[Children] = {
			C.corner(16),
			C.stroke(Theme.colors.toxic, 3),
			C.label({
				Text = "NEXT UP",
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -24, 0, 20),
				TextColor3 = Theme.colors.toxic,
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
			}),
			C.label({
				Text = Computed(function()
					return objective:get().text
				end),
				Position = UDim2.fromOffset(12, 26),
				Size = UDim2.new(1, -24, 0, 34),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				MaxTextSize = 20,
			}),
			New("Frame")({
				Name = "Bar",
				Position = UDim2.new(0, 12, 1, -18),
				Size = UDim2.new(1, -24, 0, 10),
				BackgroundColor3 = Theme.colors.slateLight,
				Visible = Computed(function()
					return objective:get().progress ~= nil
				end),
				[Children] = {
					C.corner(5),
					New("Frame")({
						BackgroundColor3 = Theme.colors.toxic,
						Size = Computed(function()
							return UDim2.fromScale(math.clamp(progress:get(), 0, 1), 1)
						end),
						[Children] = C.corner(5),
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
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(640, 130),
		MaxTextSize = 64,
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
	return { cashPill(), bagCounter(), eggBar(), actionButtons(), nextUp(), banner() }
end
