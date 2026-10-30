--!strict
-- One toast lane at the top center, one message at a time (State.toast queues the rest).
-- Good news ("success") gets a gold stripe; everything else is neutral. Never red.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Format = require(game:GetService("ReplicatedStorage").Shared.Format)
local Hud = require(game:GetService("ReplicatedStorage").Shared.Config.Hud)

-- Centered under the Cash / Gems row, like the weather line above it (UI/Hud TOP_ROW_CENTER).
local TOP = Hud.top
local CENTER = (2 * TOP.cashX + TOP.gap + Hud.faceOutline + Theme.shadow + TOP.gemsWidth) / 2

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
		Position = UDim2.new(0.5, CENTER, 0, Hud.toast.y),
		Size = UDim2.fromOffset(Hud.toast.width, Hud.toast.height),
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
								-- Good news gets a sparkle glyph; any emoji in the text (server messages
								-- also go to chat, where emoji are fine) is dropped here.
								if good
									then C.icon("sparkle", 20, nil, {
										AnchorPoint = Vector2.new(0, 0.5),
										Position = UDim2.new(0, 16, 0.5, 0),
										ZIndex = 3,
									})
									else nil,
								C.label({
									Size = UDim2.new(1, if good then -54 else -30, 1, -12),
									Position = UDim2.fromOffset(if good then 42 else 18, 6),
									MaxTextSize = 18,
									TextColor3 = if good then Theme.colors.white else Theme.colors.cream,
									Text = Format.stripEmoji(text or ""),
									ZIndex = 2,
								}),
							},
						}),
					},
				})
		end, Fusion.cleanup),
	})
end
