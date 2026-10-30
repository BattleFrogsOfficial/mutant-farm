--!strict
-- Cash upgrades: Growth Speed and Mutation Odds, 5 levels each (+10% per level). Reset on rebirth;
-- prices scale with your rebirth count (shared/Costs.lua, the server charges the same).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local INFO = {
	growthSpeed = { icon = "bolt", title = "GROWTH SPEED", what = "Eggs grow faster" },
	mutationOdds = { icon = "sparkle", title = "MUTATION ODDS", what = "More mutations while growing" },
}

local function row(kind: string, order: number)
	local cfg = (Upgrades :: any)[kind]
	local info = INFO[kind]
	-- Read the snapshot directly in each Computed (see the Fusion gotcha in CLAUDE.md).
	local function level(): number
		local snap = State.snapshot:get()
		return if snap and snap.upgrades then snap.upgrades[kind] or 0 else 0
	end
	local function cost(): number?
		local snap = State.snapshot:get()
		return if snap and snap.upgradeCosts then snap.upgradeCosts[kind] else nil
	end
	local pips: { any } = {
		New("UIListLayout")({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	}
	for i = 1, cfg.levels do
		table.insert(
			pips,
			New("Frame")({
				LayoutOrder = i,
				Size = UDim2.fromOffset(28, 14),
				BorderSizePixel = 0,
				BackgroundColor3 = Computed(function()
					return if level() >= i then Theme.colors.toxic else Theme.colors.ink
				end),
				ZIndex = 4,
			})
		)
	end
	return New("Frame")({
		Name = kind,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 120),
		BackgroundColor3 = Theme.colors.panelHi,
		BorderSizePixel = 0,
		ZIndex = 3,
		[Children] = {
			C.stroke(Theme.colors.ink, 3),
			C.icon(info.icon, 52, nil, { Position = UDim2.fromOffset(16, 20), ZIndex = 4 }),
			C.label({
				Text = info.title,
				Position = UDim2.fromOffset(84, 14),
				Size = UDim2.new(1, -300, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 22,
				ZIndex = 4,
			}),
			C.label({
				Text = Computed(function()
					return string.format(
						"%s · now +%d%%",
						info.what,
						math.floor(level() * cfg.bonusPerLevel * 100 + 0.5)
					)
				end),
				Position = UDim2.fromOffset(84, 42),
				Size = UDim2.new(1, -300, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 14,
				ZIndex = 4,
			}),
			New("Frame")({
				Name = "Pips",
				Position = UDim2.fromOffset(84, 72),
				Size = UDim2.fromOffset(200, 14),
				BackgroundTransparency = 1,
				ZIndex = 4,
				[Children] = pips,
			}),
			C.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(190, 62),
				Color = Theme.colors.toxic,
				MaxTextSize = 22,
				ZIndex = 5,
				Disabled = Computed(function()
					local c = cost()
					return c == nil or State.cash:get() < c
				end),
				Text = Computed(function()
					local c = cost()
					return if c then "+10% · " .. Format.cash(c) else "MAXED"
				end),
				OnClick = function()
					Remotes.get("BuyUpgrade"):FireServer(kind)
				end,
			}),
		},
	})
end

return function()
	return C.panel({
		Title = "Upgrades",
		Icon = "arrowUp",
		Accent = Theme.colors.toxicDark,
		Size = UDim2.fromOffset(600, 360),
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
				New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14) }),
				New("UIPadding")({ PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
				row("growthSpeed", 1),
				row("mutationOdds", 2),
				C.label({
					LayoutOrder = 3,
					Text = "Upgrades reset when you rebirth (and cost more after).",
					Size = UDim2.new(1, 0, 0, 20),
					TextColor3 = Theme.colors.muted,
					StrokeThickness = 0,
					MaxTextSize = 14,
					ZIndex = 3,
				}),
			},
		}),
	})
end
