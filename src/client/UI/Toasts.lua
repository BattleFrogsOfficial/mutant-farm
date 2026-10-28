--!strict
-- Short messages stacked under the top bar, between the Cash pill and the side menu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

local KIND = {
	info = { color = Theme.colors.slateLight, icon = "💬" },
	success = { color = Color3.fromHex("#2E9A4A"), icon = "✨" },
	error = { color = Color3.fromHex("#C0413F"), icon = "⚠️" },
}

return function()
	-- id -> "kind|text" strings so unchanged toasts aren't rebuilt.
	local byId = Computed(function()
		local out = {}
		for _, toast in State.toasts:get() do
			out[toast.id] = toast.kind .. "|" .. toast.text
		end
		return out
	end)

	return New("Frame")({
		Name = "Toasts",
		ZIndex = 20, -- above open panels
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(380, 170),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),
			ForPairs(byId, function(id: number, encoded: string)
				local kind, text = encoded:match("^(%a+)|(.*)$")
				local style = KIND[kind or "info"] or KIND.info
				return id,
					New("Frame")({
						LayoutOrder = id, -- ids only increase, so newest is last
						Size = UDim2.fromOffset(380, 46),
						BackgroundTransparency = 1,
						[Children] = {
							C.shadow(14, 4),
							New("Frame")({
								Size = UDim2.fromScale(1, 1),
								BackgroundColor3 = style.color,
								ZIndex = 1,
								[Children] = {
									C.corner(14),
									C.stroke(Theme.colors.slate, 2.5),
									C.shine(),
									C.label({
										Text = style.icon,
										Size = UDim2.fromOffset(30, 30),
										Position = UDim2.new(0, 10, 0.5, -15),
										MaxTextSize = 22,
										ZIndex = 2,
									}),
									C.label({
										Size = UDim2.new(1, -56, 1, -10),
										Position = UDim2.fromOffset(46, 5),
										TextXAlignment = Enum.TextXAlignment.Left,
										MaxTextSize = 20,
										Text = text,
										ZIndex = 2,
									}),
								},
							}),
						},
					})
			end, Fusion.cleanup),
		},
	})
end
