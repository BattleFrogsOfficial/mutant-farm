--!strict
-- The small tile on a patch of your own soil (PlotController puts it in a SurfaceGui on the
-- patch's Top face): a navy "+" on an empty patch you own, the price on the patch you can buy
-- next. Boxy like the HUD (ink outline, hard shadow, light top bevel, GothamBlack). The "+" pulses
-- during the tutorial's plant steps and is still after. Plain Instances (updated 20x a second, no
-- Fusion), built here so the UI preview can draw it. Numbers in Config/WorldUI.soil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldUI = require(ReplicatedStorage.Shared.Config.WorldUI)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

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
	shadow.BackgroundTransparency = CFG.shadowTransparency
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
	bevel.BackgroundTransparency = CFG.bevelTransparency
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
	textStroke.Thickness = CFG.textStroke
	textStroke.Parent = text
	text.Parent = tile

	return { root = root, holder = holder, scale = scale, text = text, kind = nil, priceText = nil }
end

export type Toggle = {
	button: TextButton,
	face: Frame,
	check: GuiObject,
	box: Frame,
	text: TextLabel,
	on: boolean?,
}

-- Auto-Harvest's REPLANT toggle (Config/WorldUI.soil.toggle): a navy chip in the patch's corner,
-- the whole of it a button (PlotController wires Activated). Only its face turns by `rotation`
-- (around its own center, so the tap area stays where it's drawn).
function SoilMarker.newToggle(): Toggle
	local T = CFG.toggle
	local button = Instance.new("TextButton")
	button.Name = "ReplantToggle"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Position = UDim2.fromScale(T.position[1], T.position[2])
	button.Size = UDim2.fromScale(T.size[1], T.size[2])

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BorderSizePixel = 0
	shadow.BackgroundColor3 = Theme.colors.ink
	shadow.BackgroundTransparency = CFG.shadowTransparency
	shadow.Position = UDim2.fromOffset(-CFG.shadow, -CFG.shadow) -- down-right once turned
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Rotation = CFG.rotation
	shadow.ZIndex = 1
	shadow.Parent = button

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.BackgroundColor3 = Theme.colors.navy
	face.Size = UDim2.fromScale(1, 1)
	face.Rotation = CFG.rotation
	face.ZIndex = 2
	local outline = Instance.new("UIStroke")
	outline.Color = Theme.colors.ink
	outline.Thickness = CFG.outline
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.LineJoinMode = Enum.LineJoinMode.Miter
	outline.Parent = face
	face.Parent = button

	-- Glyph square on the left of the face (sized from the canvas height of the chip).
	local px = SoilMarker.canvasPx(CFG.patchStuds)
	local h = T.size[2] * px
	local g = math.floor(h * T.glyph)
	local check = Icons.new("check", {
		Size = g,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, T.pad, 0.5, 0),
		ZIndex = 3,
	})
	check.Name = "Check"
	check.Parent = face
	local box = Instance.new("Frame")
	box.Name = "EmptyBox"
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.Position = UDim2.new(0, T.pad + 2, 0.5, 0)
	box.Size = UDim2.fromOffset(g - 4, g - 4)
	box.BackgroundColor3 = Theme.colors.slate
	box.BorderSizePixel = 0
	box.ZIndex = 3
	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Theme.colors.ink
	boxStroke.Thickness = CFG.outline - 1
	boxStroke.Parent = box
	box.Parent = face

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Position = UDim2.new(0, 2 * T.pad + g, 0, T.pad)
	text.Size = UDim2.new(1, -(3 * T.pad + g), 1, -2 * T.pad)
	text.Font = Theme.font
	-- One line, as big as fits (TextScaled would wrap it onto two tiny lines).
	local room = T.size[1] * px - (3 * T.pad + g)
	text.TextSize = math.floor(math.min(h - 2 * T.pad, room / (#T.text * T.textEm)))
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Theme.colors.white
	text.Text = T.text
	text.ZIndex = 3
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Theme.colors.ink
	textStroke.Thickness = CFG.textStroke
	textStroke.Parent = text
	text.Parent = face

	return { button = button, face = face, check = check, box = box, text = text, on = nil }
end

-- On: the check glyph and white text; off: an empty box, the chip dimmed.
function SoilMarker.setToggle(toggle: Toggle, on: boolean)
	if toggle.on == on then
		return
	end
	toggle.on = on
	toggle.check.Visible = on
	toggle.box.Visible = not on
	toggle.face.BackgroundTransparency = if on then 0 else CFG.toggle.offTransparency
	toggle.text.TextColor3 = if on then Theme.colors.white else Theme.colors.muted
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
