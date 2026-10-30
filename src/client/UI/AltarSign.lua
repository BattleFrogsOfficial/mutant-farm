--!strict
-- The Rebirth Altar's sign face, drawn per player (ZoneController mounts it in a SurfaceGui in
-- PlayerGui adorned to the sign's board, so the button can be tapped): "REBIRTH 1 · $700K" over
-- "unlocks Toxic Egg" (or "Cash x2"), a Cash / cost bar, and from 50% of the cost a pink
-- REBIRTH NOW · 100 [gem] beside the bar (it opens the Rebirth panel, where it's confirmed).
-- Design size SIZE (the board at 40 px per stud).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Products = require(Shared.Config.Products)
local Format = require(Shared.Format)
local ShopRules = require(Shared.ShopRules)
local Valuation = require(Shared.Valuation)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

local AltarSign = {}

AltarSign.SIZE = Vector2.new(560, 224) -- 14 x 5.6 studs

-- "REBIRTH 1 · $700K" / "unlocks Toxic Egg" (or "Cash x2" when it unlocks no tier).
function AltarSign.text(rebirths: number, cost: number): string
	local tier = ShopRules.unlockedAtRebirth(rebirths + 1)
	local reward = if tier
		then "unlocks " .. Eggs.tiers[tier].name
		else "Cash x" .. tostring(Valuation.rebirthMultiplier(rebirths + 1))
	return string.format("REBIRTH %d · %s\n%s", rebirths + 1, Format.cash(cost), reward)
end

function AltarSign.new(): Frame
	local offerNow = Computed(function()
		local snap = State.snapshot:get()
		return snap ~= nil and ShopRules.rebirthNowOffered(snap.cash, snap.rebirthCost or 0)
	end)
	local progress = Computed(function()
		local snap = State.snapshot:get()
		return if snap and (snap.rebirthCost or 0) > 0 then math.clamp(snap.cash / snap.rebirthCost, 0, 1) else 0
	end)
	return New("Frame")({
		Name = "AltarSign",
		Size = UDim2.fromOffset(AltarSign.SIZE.X, AltarSign.SIZE.Y),
		BackgroundColor3 = Theme.colors.purpleDark,
		BorderSizePixel = 0,
		[Children] = {
			C.label({
				Name = "Title",
				Position = UDim2.fromOffset(16, 8),
				Size = UDim2.new(1, -32, 0, 136),
				TextColor3 = Theme.colors.gold,
				MaxTextSize = 60,
				StrokeThickness = 4,
				Text = Computed(function()
					local snap = State.snapshot:get()
					return if snap then AltarSign.text(snap.rebirths, snap.rebirthCost or 0) else "REBIRTH ALTAR"
				end),
			}),
			New("Frame")({
				Name = "Bar",
				Position = UDim2.fromOffset(16, 156),
				Size = Computed(function()
					return if offerNow:get() then UDim2.new(1, -254, 0, 52) else UDim2.new(1, -32, 0, 52)
				end),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				[Children] = {
					C.stroke(Theme.colors.cream, 4),
					New("Frame")({
						Name = "Fill",
						BorderSizePixel = 0,
						BackgroundColor3 = Theme.colors.toxic,
						Size = Computed(function()
							return UDim2.fromScale(progress:get(), 1)
						end),
					}),
					C.label({
						Text = Computed(function()
							return string.format("%d%%", math.floor(progress:get() * 100))
						end),
						Size = UDim2.new(1, -16, 1, -12),
						Position = UDim2.fromOffset(8, 6),
						MaxTextSize = 34,
						StrokeThickness = 3,
						ZIndex = 2,
					}),
				},
			}),
			C.button({
				Name = "RebirthNow",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 150),
				Size = UDim2.fromOffset(214, 62),
				Color = Theme.colors.spend,
				Visible = offerNow,
				Text = string.format("REBIRTH NOW · %d", Products.gems.RebirthNow.cost),
				IconAfter = "gem",
				MaxTextSize = 22,
				OnClick = function()
					-- The panel holds the confirm (and sends short-on-Gems players to the packs).
					State.panel:set("rebirth")
				end,
			}),
		},
	})
end

return AltarSign
