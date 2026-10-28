--!strict
-- One toast lane at the top center, one message at a time (State.toast queues the rest).
-- Good news ("success") gets a gold stripe; everything else is neutral. Never red.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

return function()
	-- id -> "kind|text" so the current toast isn't rebuilt every update.
	local byId = Computed(function()
		local out = {}
		for _, toast in State.toasts:get() do
			out[toast.id] = toast.kind .. "|" .. toast.text
		end
		return out
	end)
	return New("Frame")({
		Name = "Toast",
		ZIndex = 20, -- above open panels
		AnchorPoint = Vector2.new(0.5, 0),
		-- Drops below the ☰ dropdown while it's open, so the two never cover each other.
		Position = Computed(function()
			return UDim2.new(0.5, 0, 0, if State.menuOpen:get() then 196 else 100)
		end),
		Size = UDim2.fromOffset(400, 48),
		BackgroundTransparency = 1,
		[Children] = ForPairs(byId, function(id: number, encoded: string)
			local kind, text = encoded:match("^(%a+)|(.*)$")
			local good = kind == "success"
			return id,
				New("Frame")({
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					[Children] = {
						C.shadow(),
						New("Frame")({
							Size = UDim2.fromScale(1, 1),
							BorderSizePixel = 0,
							BackgroundColor3 = Theme.colors.panel,
							ZIndex = 1,
							[Children] = {
								C.stroke(Theme.colors.ink, 3),
								C.bevel(2, 0.88),
								New("Frame")({
									Name = "Stripe",
									BorderSizePixel = 0,
									Size = UDim2.new(0, 6, 1, 0),
									BackgroundColor3 = if good then Theme.colors.gold else Theme.colors.slateLight,
									ZIndex = 2,
								}),
								C.label({
									Size = UDim2.new(1, -30, 1, -12),
									Position = UDim2.fromOffset(18, 6),
									MaxTextSize = 18,
									TextColor3 = if good then Theme.colors.white else Theme.colors.cream,
									Text = (if good then "✨ " else "") .. (text or ""),
									ZIndex = 2,
								}),
							},
						}),
					},
				})
		end, Fusion.cleanup),
	})
end
