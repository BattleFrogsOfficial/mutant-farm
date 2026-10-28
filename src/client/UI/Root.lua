--!strict
-- Everything on the main ScreenGui (UIController scales it; the hatch cinematic is separate):
-- the HUD, a dim backdrop behind open panels (tap it to close), the panels, and toasts on top.

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
local CodesPanel = require(script.Parent.CodesPanel)

local New, Children, Computed, OnEvent = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.OnEvent

return function()
	return New("Frame")({
		Name = "Main",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = Computed(function()
			return not State.hatching:get()
		end),
		[Children] = {
			Hud(),
			New("TextButton")({
				Name = "Dim",
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,
				Visible = Computed(function()
					return State.panel:get() ~= "none"
				end),
				ZIndex = 9,
				[OnEvent("Activated")] = function()
					State.panel:set("none")
				end,
			}),
			EggShop(),
			SellPanel(),
			Almanac(),
			DailyPanel(),
			WelcomePanel(),
			StorePanel(),
			SlotOfferPanel(),
			RebirthPanel(),
			CodesPanel(),
			Toasts(),
		},
	})
end
