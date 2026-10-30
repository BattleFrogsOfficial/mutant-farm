--!strict
-- "Welcome back!" card shown after a break: how long you were away, how many eggs are ready to
-- hatch (or, with Auto-Harvest, how many it hatched into your bag), and how many mutations
-- happened while you were gone. One tap goes straight to hatching.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local function stat(order: number, icon: string, value: any, label: any, color: Color3)
	return New("Frame")({
		LayoutOrder = order,
		Size = UDim2.fromOffset(160, 120),
		BackgroundColor3 = Theme.colors.slate,
		ZIndex = 2,
		[Children] = {
			C.stroke(color, 3),
			C.icon(icon, 34, nil, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, -2, 0, 10),
				ZIndex = 3,
			}),
			C.label({
				Text = value,
				Size = UDim2.new(1, -12, 0, 36),
				Position = UDim2.fromOffset(6, 48),
				MaxTextSize = 32,
				TextColor3 = color,
				StrokeThickness = 3,
				ZIndex = 3,
			}),
			C.label({
				Text = label,
				Size = UDim2.new(1, -12, 0, 22),
				Position = UDim2.fromOffset(6, 88),
				MaxTextSize = 16,
				ZIndex = 3,
			}),
		},
	})
end

return function()
	local info = State.welcome
	local function get()
		return info:get() or { away = 0, ready = 0, mutations = 0, capped = false, earned = 0 }
	end
	return C.panel({
		Title = "Welcome back!",
		Icon = "star",
		Accent = Theme.colors.toxicDark,
		Size = UDim2.fromOffset(600, 400),
		IsOpen = Computed(function()
			return State.panel:get() == "welcome"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.label({
				Text = Computed(function()
					return "Your farm kept growing for " .. Format.duration(get().away) .. " while you were gone!"
				end),
				Size = UDim2.new(1, 0, 0, 30),
				MaxTextSize = 20,
				TextColor3 = Theme.colors.cream,
				ZIndex = 2,
			}),
			New("Frame")({
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 44),
				Size = UDim2.new(1, 0, 0, 124),
				ZIndex = 2,
				[Children] = {
					New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 16),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					stat(
						0,
						"paw",
						Computed(function()
							return Format.cash(get().earned or 0)
						end),
						"pen earned",
						Theme.colors.toxic
					),
					stat(
						1,
						"egg",
						Computed(function()
							local auto = get().autoHarvested or 0
							return tostring(if auto > 0 then auto else get().ready)
						end),
						Computed(function()
							return if (get().autoHarvested or 0) > 0 then "auto-hatched" else "ready to hatch"
						end),
						Theme.colors.gold
					),
					stat(
						2,
						"sparkle",
						Computed(function()
							return tostring(get().mutations)
						end),
						"mutations",
						Theme.colors.purple
					),
				},
			}),
			C.label({
				Text = "Tip: eggs stop mutating 2 hours after you leave.",
				Position = UDim2.fromOffset(0, 178),
				Size = UDim2.new(1, 0, 0, 22),
				MaxTextSize = 16,
				TextColor3 = Theme.colors.muted,
				Visible = Computed(function()
					return get().capped
				end),
				ZIndex = 2,
			}),
			C.button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(300, 60),
				Color = Theme.colors.navy,
				Studs = true,
				MaxTextSize = 26,
				ZIndex = 3,
				Pulse = Computed(function()
					return get().ready > 0
				end),
				Text = Computed(function()
					return if get().ready > 0 then string.format("HATCH %d NOW", get().ready) else "Let's go!"
				end),
				Icon = Computed(function()
					return if get().ready > 0 then "egg" else nil
				end),
				OnClick = function()
					State.panel:set("none")
					if get().ready > 0 then
						Remotes.get("HarvestAll"):FireServer()
					end
				end,
			}),
		},
	})
end
