--!strict
-- Short messages stacked under the Cash pill.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

local KIND_COLORS = {
	info = Theme.colors.slate,
	success = Color3.fromHex("#2E7D32"),
	error = Color3.fromHex("#B23A3A"),
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
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(460, 220),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 6),
			}),
			ForPairs(byId, function(id: number, encoded: string)
				local kind, text = encoded:match("^(%a+)|(.*)$")
				return id,
					New("Frame")({
						LayoutOrder = id, -- ids only increase, so newest is last
						Size = UDim2.fromOffset(460, 44),
						BackgroundColor3 = KIND_COLORS[kind] or Theme.colors.slate,
						BackgroundTransparency = 0.1,
						[Children] = {
							C.corner(12),
							C.label({
								Size = UDim2.new(1, -20, 1, -10),
								Position = UDim2.fromOffset(10, 5),
								MaxTextSize = 22,
								Text = text,
							}),
						},
					})
			end, Fusion.cleanup),
		},
	})
end
