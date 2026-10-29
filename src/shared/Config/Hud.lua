--!strict
-- HUD layout numbers (design px on the 900x540 canvas; the whole HUD is scaled by one UIScale).
-- Logic and UI read these; tuning the layout never edits Hud.lua.

return {
	-- Scaling (shared/HudScale.lua): the HUD scales with the SHORTER screen edge against the
	-- design height, capped so big monitors don't get a giant HUD (touch screens stay at 1:1).
	designWidth = 900,
	designHeight = 540,
	minScale = 0.5,
	maxScale = 1.25, -- mouse/keyboard screens
	maxScaleTouch = 1.0, -- phones and tablets
	-- Panels are sized to their content; one wider/taller than the design canvas (a narrow window
	-- at the 1.25x cap) shrinks to fit, keeping this much space to the canvas edge.
	panelMargin = 12,

	-- Distance from the screen edges (right column, Shop, Water).
	edge = 14,

	-- Top row, directly under Roblox's top bar: Cash (centered `cashX` off the middle) and Gems.
	top = {
		y = 6,
		height = 36, -- top-row panels stay short so the HUD still sits high
		cashX = -66,
		cashWidth = 300,
		gemsWidth = 120,
		gap = 8,
		icon = 24, -- coin / gem glyphs
	},

	-- Upgrades / Daily / Almanac tiles, top-right, left to right, a fixed gap apart. The red dot is
	-- a small diamond kept inside the tile (its center `dotInset` px from the top-right corner).
	tiles = {
		width = 48,
		gap = 8,
		glyph = 22,
		glyphShift = -4, -- the glyph sits a little left of center, clear of the dot
		dot = 9,
		dotInset = 10,
	},

	-- Right column under the tiles, top to bottom: weather countdown, Instant Weather, Starter
	-- Bundle, bag count, `gap` px apart. Weather, Instant Weather and the bundle share `width`.
	column = {
		gap = 8,
		width = 200,
		weatherHeight = 22, -- plain text (hub)
		weatherChipHeight = 32, -- countdown chip (5 min before an event until it ends)
		instantHeight = 50,
		bundleHeight = 54,
		bagWidth = 130,
		bagHeight = 44,
		bagGlyph = 24,
	},

	-- SHOP: the biggest button in the hub. At the plot it is the WATER button's size, beside it.
	shop = {
		hubWidth = 230,
		hubHeight = 88,
		hubText = 36,
		plotText = 22,
	},

	-- WATER and SHOP at the plot (same size). Desktop: bottom-right, Water left of Shop when there
	-- is room right of the egg tray (`trayClearance`), else above it. Touch: mid-right, side by side
	-- (the jump button owns the corner).
	plotButtons = {
		width = 132,
		height = 64,
		gap = 8,
		glyph = 28,
		trayClearance = 12,
		ringWidth = 5, -- the drain ring along the Water button's edge
	},

	-- Egg tray (plot, bottom center): owned eggs + one "next egg" tile, HATCH on the right.
	tray = {
		width = 424,
		height = 146,
		bottom = 12,
		tileWidth = 84,
		tileHeight = 104,
		tileGap = 10,
		art = 64,
		hatchWidth = 108,
		hatchGlyph = 34,
		chatWidth = 215, -- the chat window at its smallest (WidthScale 0.5), plus margin
	},
	nextUpBottom = 190, -- Next Up's bottom edge above the screen bottom

	-- Vector glyphs (UI/Glyphs.lua): ink outline and hard shadow, in design px.
	glyph = {
		stroke = 3,
		shadow = 3,
		shadowTransparency = 0.25,
	},
}
