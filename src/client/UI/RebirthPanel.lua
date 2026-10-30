--!strict
-- Rebirth: what it costs, how close you are, what you get (Cash multiplier, the next egg tier)
-- and what resets. The button needs a second tap to confirm. From 50% of the cost (ShopRules.
-- rebirthNowOffered) a pink REBIRTH NOW · 100 💎 sits beside the progress bar (also two taps;
-- short on Gems opens the Gem shop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Rebirths = require(Shared.Config.Rebirths)
local Products = require(Shared.Config.Products)
local ShopRules = require(Shared.ShopRules)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, Value, Observer =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value, Fusion.Observer

local function line(order: number, text: any, color: Color3, icon: string?)
	if icon then
		-- The glyph, then the text fitted to the rest of the line.
		return New("Frame")({
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			[Children] = {
				C.icon(icon, 16, nil, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }),
				C.label({
					Text = text,
					Position = UDim2.fromOffset(22, 0),
					Size = UDim2.new(1, -22, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = color,
					StrokeThickness = 0,
					TextScaled = false,
					TextSize = 14,
				}),
			},
		})
	end
	return C.label({
		LayoutOrder = order,
		Text = text,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		StrokeThickness = 0,
		TextScaled = false,
		TextSize = 14,
	})
end

local function column(position: UDim2, title: string, titleColor: Color3, lines: { any })
	local children: { any } = {
		New("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		C.label({
			LayoutOrder = 0,
			Text = title,
			Size = UDim2.new(1, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = titleColor,
			MaxTextSize = 16,
		}),
	}
	for _, l in lines do
		table.insert(children, l)
	end
	return New("Frame")({
		Position = position,
		Size = UDim2.new(0.5, -8, 0, 110),
		BackgroundTransparency = 1,
		ZIndex = 3,
		[Children] = children,
	})
end

return function()
	local confirming = Value(false)
	local nowConfirming = Value(false)
	Observer(State.panel):onChange(function()
		confirming:set(false)
		nowConfirming:set(false)
	end)
	local rebirths = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.rebirths else 0
	end)
	local cost = Computed(function()
		local snap = State.snapshot:get()
		return if snap then snap.rebirthCost or 0 else 0
	end)
	local progress = Computed(function()
		local c = cost:get()
		return if c > 0 then math.clamp(State.cash:get() / c, 0, 1) else 0
	end)
	local offerNow = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and ShopRules.rebirthNowOffered(snap.cash, snap.rebirthCost or 0)
	end)
	local unlock = Computed(function()
		for _, eggId in Eggs.order do
			if Eggs.tiers[eggId].unlockRebirth == rebirths:get() + 1 then
				return Eggs.tiers[eggId].name
			end
		end
		return nil
	end)
	return C.panel({
		Title = Computed(function()
			return "Rebirth " .. (rebirths:get() + 1)
		end),
		Icon = "rebirth",
		Accent = Theme.colors.purple,
		Size = UDim2.fromOffset(640, 400),
		IsOpen = Computed(function()
			return State.panel:get() == "rebirth"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.label({
				Text = Computed(function()
					return "COSTS " .. Format.cash(cost:get())
				end),
				Size = UDim2.new(1, 0, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.colors.gold,
				MaxTextSize = 26,
				ZIndex = 3,
			}),
			New("Frame")({
				Name = "Bar",
				Position = UDim2.fromOffset(0, 38),
				Size = Computed(function()
					return if offerNow:get() then UDim2.new(1, -206, 0, 24) else UDim2.new(1, 0, 0, 24)
				end),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				ZIndex = 3,
				[Children] = {
					New("Frame")({
						BorderSizePixel = 0,
						BackgroundColor3 = Theme.colors.purple,
						Size = Computed(function()
							return UDim2.fromScale(progress:get(), 1)
						end),
						ZIndex = 4,
					}),
					C.label({
						Text = Computed(function()
							return string.format(
								"%s / %s  ·  %d%%",
								Format.cash(State.cash:get()),
								Format.cash(cost:get()),
								math.floor(progress:get() * 100)
							)
						end),
						Size = UDim2.new(1, -10, 1, -6),
						Position = UDim2.fromOffset(5, 3),
						MaxTextSize = 16,
						ZIndex = 5,
					}),
				},
			}),
			-- Rebirth Now, beside the bar while 50% <= Cash < cost.
			C.button({
				Name = "RebirthNow",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0, 50),
				Size = UDim2.fromOffset(196, 42),
				Color = Theme.colors.spend,
				Visible = offerNow,
				MaxTextSize = 17,
				IconAfter = "gem",
				IconSize = 20,
				ZIndex = 4,
				Text = Computed(function()
					return if nowConfirming:get()
						then string.format("TAP AGAIN · %d", Products.gems.RebirthNow.cost)
						else string.format("REBIRTH NOW · %d", Products.gems.RebirthNow.cost)
				end),
				OnClick = function()
					if State.gems:get(false) < Products.gems.RebirthNow.cost then
						State.panel:set("store") -- short on Gems: straight to the packs
						return
					end
					if not nowConfirming:get(false) then
						nowConfirming:set(true)
						return
					end
					nowConfirming:set(false)
					Remotes.get("RebirthNow"):FireServer()
					State.panel:set("none")
				end,
			}),
			column(UDim2.fromOffset(0, 80), "YOU GET", Theme.colors.toxic, {
				line(
					1,
					Computed(function()
						-- From the server's multiplier, so VIP's 1.5x is included.
						local snap = State.snapshot:get()
						local now = if snap then snap.cashMultiplier else 1
						local base = 1 + Rebirths.cashBonusPerRebirth * rebirths:get()
						local nextMult = now * (base + Rebirths.cashBonusPerRebirth) / base
						return string.format("Cash x%s = x%s forever", tostring(now), tostring(nextMult))
					end),
					Theme.colors.white,
					"coin"
				),
				line(
					2,
					Computed(function()
						local name = unlock:get()
						return if name then name .. " unlocked" else "Bigger egg prices, bigger value"
					end),
					Theme.colors.white,
					"egg"
				),
				line(3, "Keep pen, passes, Gems, Almanac", Theme.colors.white, "check"),
			}),
			column(UDim2.new(0.5, 8, 0, 80), "RESETS", Theme.colors.danger, {
				line(1, "Cash, eggs and growing plants", Theme.colors.cream),
				line(2, "Bought soil patches", Theme.colors.cream),
				line(3, "Bag is sold (your pen stays)", Theme.colors.cream),
			}),
			C.button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(300, 60),
				Studs = true,
				Color = Computed(function()
					return if confirming:get() then Theme.colors.navy else Theme.colors.purple
				end),
				Disabled = Computed(function()
					return progress:get() < 1
				end),
				Pulse = Computed(function()
					return progress:get() >= 1
				end),
				MaxTextSize = 24,
				ZIndex = 4,
				Text = Computed(function()
					if progress:get() < 1 then
						return "NEED " .. Format.cash(math.max(0, cost:get() - State.cash:get())) .. " MORE"
					end
					return if confirming:get() then "TAP AGAIN TO CONFIRM" else "REBIRTH NOW"
				end),
				OnClick = function()
					if not confirming:get(false) then
						confirming:set(true)
						return
					end
					confirming:set(false)
					Remotes.get("Rebirth"):FireServer()
					State.panel:set("none")
				end,
			}),
		},
	})
end
