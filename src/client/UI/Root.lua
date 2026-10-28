--!strict
-- Everything on the main ScreenGui (UIController scales it; the hatch cinematic is separate):
-- the HUD, the panels, and toasts on top. The dim backdrop behind open panels is UI/Backdrop, in
-- its own full-screen ScreenGui (it has to cover Roblox's top-bar strip too).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)
local Hud = require(script.Parent.Hud)
local Toasts = require(script.Parent.Toasts)
local EggShop = require(script.Parent.EggShop)
local SellPanel = require(script.Parent.SellPanel)
local Almanac = require(script.Parent.Almanac)
local DailyPanel = require(script.Parent.DailyPanel)
local WelcomePanel = require(script.Parent.WelcomePanel)
local StorePanel = require(script.Parent.StorePanel)
local SlotOfferPanel = require(script.Parent.SlotOfferPanel)
local RebirthPanel = require(script.Parent.RebirthPanel)
local UpgradesPanel = require(script.Parent.UpgradesPanel)

local New, Children, Computed = Fusion.New, Fusion.Children, Fusion.Computed

return function()
	return New("Frame")({
		Name = "Main",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = Computed(function()
			return not State.hatching:get()
		end),
		[Children] = {
			-- The HUD hides while any panel is open, so panels never fight HUD buttons.
			New("Frame")({
				Name = "Hud",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = Computed(function()
					return State.panel:get() == "none"
				end),
				[Children] = Hud(),
			}),
			EggShop(),
			SellPanel(),
			Almanac(),
			DailyPanel(),
			WelcomePanel(),
			StorePanel(),
			SlotOfferPanel(),
			RebirthPanel(),
			UpgradesPanel(),
			Toasts(),
		},
	})
end
