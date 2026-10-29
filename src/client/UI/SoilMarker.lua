--!strict
-- The small tile on a patch of your own soil (PlotController puts it in a SurfaceGui on the
-- patch's Top face): a navy "+" on an empty patch you own, the price on the patch you can buy
-- next. Boxy like the HUD (ink outline, hard shadow, light top bevel, GothamBlack). The "+" pulses
-- during the tutorial's plant steps and is still after. Plain Instances (updated 20x a second, no
-- Fusion), built here so the UI preview can draw it. Numbers in Config/WorldUI.soil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldUI = require(ReplicatedStorage.Shared.Config.WorldUI)
local Theme = require(script.Parent.Theme)

local SoilMarker = {}

local CFG = WorldUI.soil

export type Kind = "plus" | "price"
export type Marker = {
	root: Frame,
	holder: Frame,
	scale: UIScale,
	text: TextLabel,
	kind: Kind?,
	priceText: string?,
}

-- Canvas size in px of a patch `studs` wide (the SurfaceGui's pixel size).
function SoilMarker.canvasPx(studs: number): number
	return studs * CFG.pixelsPerStud
end

-- Pulse scale at clock time t (seconds).
function SoilMarker.pulseScale(t: number): number
	return 1 + CFG.pulseAmount * math.abs(math.sin(t * CFG.pulseSpeed))
end

function SoilMarker.new(): Marker
	local root = Instance.new("Frame")
	root.Name = "SoilMarker"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1

	-- Holder: the tile's footprint, centered on the patch; it rotates (to face the gate) and
	-- pulses as one piece, shadow included.
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(CFG.plusSize[1], CFG.plusSize[2])
	holder.BackgroundTransparency = 1
	holder.Rotation = CFG.rotation
	holder.Parent = root
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = holder

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BorderSizePixel = 0
	shadow.BackgroundColor3 = Theme.colors.ink
	shadow.BackgroundTransparency = 0.2
	shadow.Position = UDim2.fromOffset(CFG.shadow, CFG.shadow)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.ZIndex = 1
	shadow.Parent = holder

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.BorderSizePixel = 0
	tile.BackgroundColor3 = Theme.colors.navy
	tile.Size = UDim2.fromScale(1, 1)
	tile.ZIndex = 2
	local outline = Instance.new("UIStroke")
	outline.Color = Theme.colors.ink
	outline.Thickness = CFG.outline
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.LineJoinMode = Enum.LineJoinMode.Miter
	outline.Parent = tile
	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.BorderSizePixel = 0
	bevel.BackgroundColor3 = Theme.colors.white
	bevel.BackgroundTransparency = 0.75
	bevel.Size = UDim2.new(1, 0, 0, CFG.bevel)
	bevel.ZIndex = 3
	bevel.Parent = tile
	tile.Parent = holder

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.new(1, -2 * CFG.textInset.plus, 1, -2 * CFG.textInset.plus)
	text.Font = Theme.font
	text.TextScaled = true
	text.TextColor3 = Theme.colors.white
	text.Text = "+"
	text.ZIndex = 4
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.colors.ink
	textStroke.Thickness = 2
	textStroke.Parent = text
	text.Parent = tile

	return { root = root, holder = holder, scale = scale, text = text, kind = nil, priceText = nil }
end

-- kind "plus" (empty patch) or "price" (the next patch to buy, priceText like "$675");
-- pulse is the current scale (1 = still).
function SoilMarker.set(marker: Marker, kind: Kind, priceText: string?, pulse: number)
	if marker.kind ~= kind or marker.priceText ~= priceText then
		marker.kind = kind
		marker.priceText = priceText
		local size = if kind == "price" then CFG.priceSize else CFG.plusSize
		marker.holder.Size = UDim2.fromScale(size[1], size[2])
		local inset = CFG.textInset[kind]
		marker.text.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
		marker.text.Text = if kind == "price" then priceText or "" else "+"
	end
	if marker.scale.Scale ~= pulse then
		marker.scale.Scale = pulse
	end
end

return SoilMarker
