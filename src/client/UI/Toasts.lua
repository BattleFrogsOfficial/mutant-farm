--!strict
-- Short messages in two lanes. The center lane under the top strip is for good news only
-- ("success": mutations, hatches, purchases). Everything else ("info"/"error") is a small neutral
-- hint just above the egg tray: never red, never covering the farm or a celebration.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local New, Children, Computed, ForPairs = Fusion.New, Fusion.Children, Fusion.Computed, Fusion.ForPairs

local function lane(good: boolean)
	-- id -> text, only this lane's toasts, so unchanged toasts aren't rebuilt.
	local byId = Computed(function()
		local out = {}
		for _, toast in State.toasts:get() do
			if (toast.kind == "success") == good then
				out[toast.id] = toast.text
			end
		end
		return out
	end)
	local width = if good then 400 else 340
	local height = if good then 48 else 34
	return New("Frame")({
		Name = if good then "GoodNews" else "Hints",
		ZIndex = 20, -- above open panels
		AnchorPoint = Vector2.new(0.5, if good then 0 else 1),
		Position = if good then UDim2.new(0.5, 0, 0, 92) else UDim2.new(0.5, 0, 1, -172),
		Size = UDim2.fromOffset(width, 3 * (height + 8)),
		BackgroundTransparency = 1,
		[Children] = {
			New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = if good then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 8),
			}),
			ForPairs(byId, function(id: number, text: string)
				return id,
					New("Frame")({
						LayoutOrder = id, -- ids only increase, so newest is last
						Size = UDim2.fromOffset(width, height),
						BackgroundTransparency = 1,
						[Children] = {
							C.shadow(),
							New("Frame")({
								Size = UDim2.fromScale(1, 1),
								BorderSizePixel = 0,
								BackgroundColor3 = if good then Color3.fromHex("#2E9A4A") else Theme.colors.panel,
								BackgroundTransparency = if good then 0 else 0.1,
								ZIndex = 1,
								[Children] = {
									C.stroke(Theme.colors.ink, 3),
									C.bevel(2, if good then 0.6 else 0.88),
									New("Frame")({
										Name = "Stripe",
										BorderSizePixel = 0,
										Size = UDim2.new(0, 5, 1, 0),
										BackgroundColor3 = if good then Theme.colors.gold else Theme.colors.muted,
										ZIndex = 2,
									}),
									C.label({
										Size = UDim2.new(1, -30, 1, -12),
										Position = UDim2.fromOffset(18, 6),
										MaxTextSize = if good then 19 else 15,
										TextColor3 = if good then Theme.colors.white else Theme.colors.cream,
										Text = (if good then "✨ " else "") .. text,
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

return function()
	return New("Frame")({
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		[Children] = { lane(true), lane(false) },
	})
end
