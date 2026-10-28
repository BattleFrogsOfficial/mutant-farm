--!strict
-- The Robux store: the Starter Bundle (while its offer runs), Gem packs, and every game pass.
-- Buttons only open Roblox's purchase prompt (Purchase.lua); MonetizationService grants.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Passes = require(Shared.Config.Passes)
local Products = require(Shared.Config.Products)
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Purchase = require(script.Parent.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local GEM = Color3.fromHex("#4FD8FF")
local PINK = Theme.colors.spend

local PASS_ORDER = { "Luck2x", "AutoHarvest", "GrowthSpeed2x", "PlotSlots10", "OfflineMutations", "VIP" }
local PASS_ICON = {
	Luck2x = "🍀",
	AutoHarvest = "🤖",
	GrowthSpeed2x = "⚡",
	PlotSlots10 = "🌱",
	OfflineMutations = "🌙",
	VIP = "👑",
}
-- +10 Plot Slots is only sold while it would give all ten (bought slots <= max - 10).
local function slotsPassUseful(): boolean
	local snap = State.snapshot:get()
	return snap == nil or snap.slotCount <= Upgrades.slots.max - 10
end

local GEM_ORDER = { "Gems100", "Gems550", "Gems1500", "Gems4000" }

local function sectionTitle(order: number, text: string, visible: any?)
	return C.label({
		LayoutOrder = order,
		Visible = visible,
		Text = text,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
		TextColor3 = Theme.colors.cream,
	})
end

local function box(props: { [string]: any })
	return New("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = props.Size,
		BackgroundTransparency = 1,
		Visible = props.Visible,
		[Children] = {
			C.shadow(),
			New("Frame")({
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = props.Color or Theme.colors.panelHi,
				ZIndex = 1,
				[Children] = {
					C.stroke(Theme.colors.ink, 3),
					C.bevel(2, 0.85),
					props.Children,
				},
			}),
		},
	})
end

local function bundleBanner()
	local offer = Products.robux.StarterBundle
	local left = Computed(function()
		local snap = State.snapshot:get()
		return (if snap then snap.bundleOfferEndsAt or 0 else 0) - State.now:get()
	end)
	return box({
		Name = "Bundle",
		LayoutOrder = 1,
		Size = UDim2.new(1, -8, 0, 92),
		Color = PINK:Lerp(Theme.colors.ink, 0.25),
		Visible = Computed(function()
			return left:get() > 0
		end),
		Children = {
			C.label({
				Text = "🎁",
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(70, 70),
				MaxTextSize = 56,
				ZIndex = 2,
			}),
			C.label({
				Text = "STARTER BUNDLE",
				Position = UDim2.fromOffset(90, 8),
				Size = UDim2.new(1, -300, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 24,
				TextColor3 = Color3.fromHex("#FFF3A8"),
				ZIndex = 2,
			}),
			C.label({
				Text = string.format("2x LUCK + AUTO-HARVEST + %d 💎", offer.grants.gems),
				Position = UDim2.fromOffset(90, 38),
				Size = UDim2.new(1, -300, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
				ZIndex = 2,
			}),
			C.label({
				Text = Computed(function()
					local s = math.max(0, math.floor(left:get()))
					return string.format("ONLY ONCE · ENDS IN %d:%02d", s // 60, s % 60)
				end),
				Position = UDim2.fromOffset(90, 62),
				Size = UDim2.new(1, -300, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.gold,
				MaxTextSize = 14,
				ZIndex = 2,
			}),
			C.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(170, 56),
				Color = PINK,
				Text = "R$ " .. offer.price,
				Studs = true,
				MaxTextSize = 24,
				Pulse = true,
				ZIndex = 3,
				OnClick = function()
					Purchase.product("StarterBundle")
				end,
			}),
		},
	})
end

local function gemCard(productId: string, order: number)
	local product = (Products.robux :: any)[productId]
	return box({
		Name = productId,
		LayoutOrder = order,
		Size = UDim2.fromOffset(134, 120),
		Children = {
			product.tag and New("Frame")({
				Name = "Tag",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(104, 20),
				BackgroundColor3 = Theme.colors.danger,
				BorderSizePixel = 0,
				ZIndex = 4,
				[Children] = {
					C.stroke(Theme.colors.ink, 2),
					C.label({
						Text = string.upper(product.tag),
						Size = UDim2.new(1, -6, 1, -4),
						Position = UDim2.fromOffset(3, 2),
						MaxTextSize = 12,
						ZIndex = 5,
					}),
				},
			}) or nil,
			C.label({
				Text = "💎",
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.new(1, 0, 0, 34),
				MaxTextSize = 32,
				ZIndex = 2,
			}),
			C.label({
				Text = Format.number(product.gems),
				Position = UDim2.fromOffset(6, 44),
				Size = UDim2.new(1, -12, 0, 22),
				TextColor3 = GEM,
				MaxTextSize = 22,
				ZIndex = 2,
			}),
			C.button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -16, 0, 40),
				Color = PINK,
				Text = "R$ " .. product.price,
				MaxTextSize = 18,
				ZIndex = 3,
				OnClick = function()
					Purchase.product(productId)
				end,
			}),
		},
	})
end

local function passCard(passId: string, order: number)
	local pass = (Passes :: any)[passId]
	local owned = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and snap.ownedPasses ~= nil and snap.ownedPasses[passId] == true
	end)
	return box({
		Name = passId,
		LayoutOrder = order,
		Size = UDim2.fromOffset(182, 112),
		Visible = if passId == "PlotSlots10"
			then Computed(function()
				return owned:get() or slotsPassUseful()
			end)
			else nil,
		Children = {
			C.label({
				Text = PASS_ICON[passId] or "⭐",
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(36, 36),
				MaxTextSize = 30,
				ZIndex = 2,
			}),
			C.label({
				Text = string.upper(pass.name),
				Position = UDim2.fromOffset(50, 8),
				Size = UDim2.new(1, -58, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 15,
				ZIndex = 2,
			}),
			C.label({
				Text = pass.description,
				Position = UDim2.fromOffset(50, 28),
				Size = UDim2.new(1, -58, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextColor3 = Theme.colors.muted,
				StrokeThickness = 0,
				MaxTextSize = 11,
				ZIndex = 2,
			}),
			C.button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -16, 0, 40),
				Color = Computed(function()
					return if owned:get() then Theme.colors.navy else PINK
				end),
				Text = Computed(function()
					return if owned:get() then "✅ OWNED" else "R$ " .. pass.price
				end),
				MaxTextSize = 18,
				ZIndex = 3,
				OnClick = function()
					if not owned:get(false) then
						Purchase.pass(passId)
					end
				end,
			}),
		},
	})
end

-- What Gems buy: the Luck Potion (hidden where PolicyService restricts paid odds boosts).
-- Skip Timer is sold where it's needed, on the egg tray.
local function potionCard()
	local potion = Products.gems.LuckPotion
	local function active(): number
		local snap = State.snapshot:get()
		return if snap then math.max(0, (snap.potionUntil or 0) - State.now:get()) else 0
	end
	return box({
		Name = "LuckPotion",
		LayoutOrder = 7,
		Size = UDim2.new(1, -8, 0, 84),
		Visible = Computed(function()
			local snap = State.snapshot:get()
			return snap ~= nil and snap.paidRandomRestricted == false
		end),
		Children = {
			C.label({
				Text = "🍀",
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(64, 64),
				MaxTextSize = 50,
				ZIndex = 2,
			}),
			C.label({
				Text = string.format("LUCK POTION · %dx LUCK FOR 30 MIN", potion.luck),
				Position = UDim2.fromOffset(84, 12),
				Size = UDim2.new(1, -290, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				ZIndex = 2,
			}),
			C.label({
				Text = Computed(function()
					local left = active()
					if left > 0 then
						return string.format("Active · %d:%02d left (buying adds 30 min)", left // 60, left % 60)
					end
					return "Rarer mutants, more mutations, bigger sizes. Stacks with 2x Luck."
				end),
				Position = UDim2.fromOffset(84, 40),
				Size = UDim2.new(1, -290, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 13,
				ZIndex = 2,
			}),
			C.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(180, 54),
				Color = PINK,
				Text = string.format("%d 💎", potion.cost),
				MaxTextSize = 22,
				ZIndex = 3,
				OnClick = function()
					if State.gems:get(false) < potion.cost then
						State.toast(string.format("Need %d Gems: grab a pack above!", potion.cost), "info")
						return
					end
					Remotes.get("BuyPotion"):FireServer()
				end,
			}),
		},
	})
end

-- Instant Weather: a 2-minute event on your own plot, for Gems (opens the picker). Hidden where
-- PolicyService restricts paid odds boosts, like the potion.
local function instantWeatherCard()
	local cost = Products.gems.InstantWeather.cost
	return box({
		Name = "InstantWeather",
		LayoutOrder = 8,
		Size = UDim2.new(1, -8, 0, 84),
		Visible = Computed(function()
			local snap = State.snapshot:get()
			return snap ~= nil and snap.paidRandomRestricted == false
		end),
		Children = {
			C.label({
				Text = "⛈",
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(64, 64),
				MaxTextSize = 50,
				ZIndex = 2,
			}),
			C.label({
				Text = "INSTANT WEATHER · ON YOUR FARM",
				Position = UDim2.fromOffset(84, 12),
				Size = UDim2.new(1, -290, 0, 24),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				ZIndex = 2,
			}),
			C.label({
				Text = "Acid Rain, Solar Flare or Glitch Storm for 2 minutes, just on your plot.",
				Position = UDim2.fromOffset(84, 40),
				Size = UDim2.new(1, -290, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 13,
				ZIndex = 2,
			}),
			C.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(180, 54),
				Color = PINK,
				Text = string.format("%d 💎", cost),
				MaxTextSize = 22,
				ZIndex = 3,
				OnClick = function()
					State.panel:set("instantWeather")
				end,
			}),
		},
	})
end

local function row(order: number, height: number, children: { any })
	table.insert(
		children,
		New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
		})
	)
	return New("Frame")({
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		[Children] = children,
	})
end

return function()
	local gems = {}
	for i, id in GEM_ORDER do
		table.insert(gems, gemCard(id, i))
	end
	local passes = {}
	for i, id in PASS_ORDER do
		table.insert(passes, passCard(id, i))
	end
	return C.panel({
		Title = "🛒 Shop",
		Accent = PINK,
		Size = UDim2.fromOffset(620, 470),
		IsOpen = Computed(function()
			return State.panel:get() == "store"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = New("ScrollingFrame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Theme.colors.muted,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 3,
			[Children] = {
				New("UIPadding")({ PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 4) }),
				New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
				bundleBanner(),
				sectionTitle(2, "💎 GEMS"),
				row(3, 128, gems),
				sectionTitle(4, "⭐ GAME PASSES · FOREVER"),
				row(5, 2 * 112 + 12 + 4, passes),
				sectionTitle(
					6,
					"🍀 SPEND GEMS",
					Computed(function()
						local snap = State.snapshot:get()
						return snap ~= nil and snap.paidRandomRestricted == false
					end)
				),
				potionCard(),
				instantWeatherCard(),
			},
		}),
	})
end
