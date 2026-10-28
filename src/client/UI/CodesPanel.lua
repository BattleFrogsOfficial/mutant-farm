--!strict
-- Type a code (from YouTubers, the group, Discord) and redeem it. The server answers with a toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, Value, OnChange =
	Fusion.New, Fusion.Children, Fusion.Computed, Fusion.Value, Fusion.OnChange

return function()
	local text = Value("")
	local function redeem()
		local code = text:get(false)
		if #code > 0 then
			Remotes.get("RedeemCode"):FireServer(string.sub(code, 1, 32))
			text:set("")
		end
	end
	return C.panel({
		Title = "🐦 Codes",
		Accent = Theme.colors.waterDark,
		Size = UDim2.fromOffset(480, 280),
		IsOpen = Computed(function()
			return State.panel:get() == "codes"
		end),
		OnClose = function()
			State.panel:set("none")
		end,
		Content = {
			C.label({
				Text = "Follow the group and our YouTubers for free Gems and eggs!",
				Size = UDim2.new(1, 0, 0, 40),
				TextWrapped = true,
				TextColor3 = Theme.colors.cream,
				StrokeThickness = 0,
				MaxTextSize = 16,
				ZIndex = 3,
			}),
			New("TextBox")({
				Name = "Input",
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.new(1, 0, 0, 56),
				BackgroundColor3 = Theme.colors.ink,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				PlaceholderText = "ENTER CODE",
				PlaceholderColor3 = Theme.colors.muted,
				Text = text,
				TextColor3 = Theme.colors.white,
				Font = Theme.font,
				TextSize = 24,
				ZIndex = 3,
				[OnChange("Text")] = function(new: string)
					text:set(new)
				end,
				[Children] = C.stroke(Theme.colors.waterDark, 3),
			}),
			C.button({
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(260, 58),
				Color = Theme.colors.toxic,
				Text = "REDEEM",
				MaxTextSize = 24,
				ZIndex = 4,
				OnClick = redeem,
			}),
		},
	})
end
