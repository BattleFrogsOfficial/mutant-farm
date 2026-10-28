--!strict
-- The dim backdrop behind open panels: covers the whole screen edge to edge, including the strip
-- under Roblox's top bar, so it lives in its own ScreenGui with IgnoreGuiInset (UIController puts
-- it just under the main GUI). Tapping it closes the open panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)

local New, Computed, OnEvent = Fusion.New, Fusion.Computed, Fusion.OnEvent

return function()
	return New("TextButton")({
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = Computed(function()
			return State.panel:get() ~= "none" and not State.hatching:get()
		end),
		[OnEvent("Activated")] = function()
			State.panel:set("none")
		end,
	})
end
