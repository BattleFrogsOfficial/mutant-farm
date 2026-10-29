--!strict
-- Flat vector-style icons built from Frames, in the boxy style (no images, no emoji, no UICorner).
-- A glyph is a list of rects in a unit box: { x, y, w, h, color, rot = true (45 degrees),
-- detail = true }. It is drawn in three layers so overlapping shapes read as one silhouette with
-- no seams inside it:
--   shadow   every outlined shape grown by the stroke, in ink, offset down-right by the boxy hard
--            shadow (Theme.shadow); the parts are opaque inside a CanvasGroup that is faded as a
--            whole (Config/Hud glyph.shadowTransparency, C.shadow's 0.2), so overlapping shapes
--            don't stack into darker seams. The group is twice the glyph's size, centered on it,
--            because a CanvasGroup clips to its bounds.
--   outline  the same grown shapes in solid ink
--   fill     the shapes in their colors; `detail` rects (ribbons, page lines, highlights) are
--            drawn only here, on top, without an outline
-- Glyphs.new(name, props) -> Frame (Name "Glyph"; attribute Glyph = name). props: Size (a UDim2 or
-- a number of px, square), Position, AnchorPoint, ZIndex, Stroke, Shadow, Visible, LayoutOrder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Theme)
local HudConfig = require(ReplicatedStorage.Shared.Config.Hud)

local New, Children = Fusion.New, Fusion.Children

local c = Theme.colors

export type Rect = { [any]: any }

local Glyphs = {}

-- Unit-box shapes. Keep them chunky: a glyph is ~20-34 px on screen, under a 3 px outline.
Glyphs.shapes = {
	-- Upgrades: a stepped arrow pointing up.
	arrowUp = {
		{ 0.4, 0.04, 0.2, 0.14, c.toxic },
		{ 0.28, 0.16, 0.44, 0.14, c.toxic },
		{ 0.15, 0.28, 0.7, 0.14, c.toxic },
		{ 0.04, 0.4, 0.92, 0.14, c.toxic },
		{ 0.32, 0.52, 0.36, 0.44, c.toxic },
		{ 0.4, 0.1, 0.08, 0.12, Theme.colors.white, detail = true },
	},
	-- Daily: a gift box with a gold ribbon and bow.
	gift = {
		{ 0.24, 0.04, 0.22, 0.22, c.gold, rot = true },
		{ 0.54, 0.04, 0.22, 0.22, c.gold, rot = true },
		{ 0.12, 0.44, 0.76, 0.52, c.purple },
		{ 0.04, 0.26, 0.92, 0.2, c.purple },
		{ 0.04, 0.42, 0.92, 0.05, c.purpleDark, detail = true },
		{ 0.42, 0.26, 0.16, 0.7, c.gold, detail = true },
	},
	-- Almanac: an open book (two cream pages on a purple cover).
	book = {
		{ 0.0, 0.3, 1.0, 0.62, c.purple },
		{ 0.06, 0.12, 0.42, 0.72, c.cream },
		{ 0.52, 0.12, 0.42, 0.72, c.cream },
		{ 0.46, 0.18, 0.08, 0.74, c.purpleDark, detail = true },
		{ 0.13, 0.28, 0.28, 0.07, c.muted, detail = true },
		{ 0.13, 0.44, 0.28, 0.07, c.muted, detail = true },
		{ 0.13, 0.6, 0.2, 0.07, c.muted, detail = true },
		{ 0.59, 0.28, 0.28, 0.07, c.muted, detail = true },
		{ 0.59, 0.44, 0.28, 0.07, c.muted, detail = true },
		{ 0.59, 0.6, 0.2, 0.07, c.muted, detail = true },
	},
	-- Cash: a blocky gold coin with a stamped bar.
	coin = {
		{ 0.26, 0.04, 0.48, 0.92, c.gold },
		{ 0.04, 0.26, 0.92, 0.48, c.gold },
		{ 0.12, 0.12, 0.76, 0.76, c.gold },
		{ 0.42, 0.24, 0.16, 0.52, c.goldDark, detail = true },
		{ 0.18, 0.2, 0.08, 0.2, Theme.colors.white, detail = true },
	},
	-- Gems: a cut gem (a diamond with a light facet).
	gem = {
		{ 0.17, 0.17, 0.66, 0.66, c.water, rot = true },
		-- (the dark facet stays inside the main diamond: |dx| + |dy| + half-diagonal <= 0.467)
		{ 0.43, 0.43, 0.3, 0.3, c.waterDark, rot = true, detail = true },
		{ 0.34, 0.28, 0.14, 0.14, Theme.colors.white, rot = true, detail = true },
	},
	-- HATCH: a blocky egg with green spots.
	egg = {
		{ 0.32, 0.02, 0.36, 0.96, c.cream },
		{ 0.2, 0.14, 0.6, 0.8, c.cream },
		{ 0.1, 0.36, 0.8, 0.5, c.cream },
		{ 0.3, 0.3, 0.14, 0.12, c.toxicDark, detail = true },
		{ 0.56, 0.5, 0.16, 0.14, c.toxicDark, detail = true },
		{ 0.3, 0.68, 0.12, 0.1, c.toxicDark, detail = true },
	},
	-- Bag: a sack tied at the neck, flared on top, round-ish at the bottom.
	bag = {
		{ 0.24, 0.05, 0.18, 0.18, c.goldDark, rot = true },
		{ 0.58, 0.05, 0.18, 0.18, c.goldDark, rot = true },
		{ 0.36, 0.08, 0.28, 0.26, c.goldDark },
		{ 0.2, 0.34, 0.6, 0.62, c.goldDark },
		{ 0.08, 0.48, 0.84, 0.36, c.goldDark },
		{ 0.3, 0.27, 0.4, 0.09, c.ink, detail = true },
		{ 0.22, 0.5, 0.1, 0.26, c.gold, detail = true },
	},
	-- Water: a stepped drop.
	drop = {
		{ 0.4, 0.02, 0.2, 0.18, c.water },
		{ 0.3, 0.18, 0.4, 0.18, c.water },
		{ 0.18, 0.34, 0.64, 0.2, c.water },
		{ 0.1, 0.5, 0.8, 0.32, c.water },
		{ 0.2, 0.78, 0.6, 0.2, c.water },
		{ 0.22, 0.54, 0.1, 0.22, Theme.colors.white, detail = true },
	},
}

local function rectFrame(r: Rect, grow: number, offset: number, color: Color3, z: number)
	return New("Frame")({
		Name = "Part",
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		Position = UDim2.new(r[1], offset - grow, r[2], offset - grow),
		Size = UDim2.new(r[3], 2 * grow, r[4], 2 * grow),
		Rotation = if r.rot then 45 else 0,
		ZIndex = z,
	})
end

function Glyphs.new(name: string, props: { [string]: any }?): any
	local p = props or {}
	local shape = Glyphs.shapes[name]
	assert(shape, "unknown glyph " .. tostring(name))
	local stroke = p.Stroke or HudConfig.glyph.stroke
	local shadow = p.Shadow or HudConfig.glyph.shadow or Theme.shadow
	local z = p.ZIndex or 4
	local layers = { shadow = {}, outline = {}, fill = {} }
	for _, r in shape do
		if not r.detail then
			table.insert(layers.shadow, rectFrame(r, stroke, shadow, Theme.colors.ink, z))
			table.insert(layers.outline, rectFrame(r, stroke, 0, Theme.colors.ink, z + 1))
		end
	end
	-- Fills: outlined shapes first, details on top of them.
	for _, r in shape do
		if not r.detail then
			table.insert(layers.fill, rectFrame(r, 0, 0, r[5], z + 2))
		end
	end
	for _, r in shape do
		if r.detail then
			table.insert(layers.fill, rectFrame(r, 0, 0, r[5], z + 3))
		end
	end
	local function layer(layerName: string, children: { any }, lz: number)
		return New("Frame")({
			Name = layerName,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = lz,
			[Children] = children,
		})
	end
	-- The shadow fades as one: a CanvasGroup with a margin of half the glyph on every side (the
	-- grown, offset and rotated shapes stay inside it), the parts in an inner glyph-sized box.
	local shadowLayer = New("CanvasGroup")({
		Name = "Shadow",
		BackgroundTransparency = 1,
		GroupTransparency = HudConfig.glyph.shadowTransparency,
		Position = UDim2.fromScale(-0.5, -0.5),
		Size = UDim2.fromScale(2, 2),
		ZIndex = z,
		[Children] = New("Frame")({
			Name = "Box",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.25, 0.25),
			Size = UDim2.fromScale(0.5, 0.5),
			ZIndex = z,
			[Children] = layers.shadow,
		}),
	})
	local size = p.Size
	if typeof(size) == "number" then
		size = UDim2.fromOffset(size, size)
	end
	local frame = New("Frame")({
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = size or UDim2.fromOffset(24, 24),
		Position = p.Position,
		AnchorPoint = p.AnchorPoint,
		LayoutOrder = p.LayoutOrder,
		Visible = p.Visible,
		ZIndex = z,
		[Children] = {
			shadowLayer,
			layer("Outline", layers.outline, z + 1),
			layer("Fill", layers.fill, z + 2),
		},
	})
	frame:SetAttribute("Glyph", name)
	return frame
end

return Glyphs
