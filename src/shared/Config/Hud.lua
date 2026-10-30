--!strict
-- HUD layout numbers (design px on the 900x540 canvas; the whole HUD is scaled by one UIScale).
-- Logic and UI read these; tuning the layout never edits Hud.lua.

return {
	-- Scaling (shared/HudScale.lua): the HUD scales with the SHORTER screen edge against the
	-- design height, capped so big monitors don't get a giant HUD (touch devices stay at 1:1), and
	-- never so far that the canvas gets narrower than designWidth (4:3 / docked windows) or that
	-- Cash reaches into Roblox's top-left chat window (`top.chatWidth`).
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
	-- Buttons and pills draw a 3 px ink outline outside their frame and a hard shadow (Theme.shadow)
	-- below-right of it. Gaps below are what you SEE between those drawn edges, so frames are spaced
	-- gap + faceOutline + Theme.shadow apart.
	faceOutline = 3,

	-- Top row, directly under Roblox's top bar: Cash (centered `cashX` off the middle) and Gems.
	top = {
		y = 6,
		height = 36, -- top-row panels stay short so the HUD still sits high
		cashX = -66,
		cashWidth = 300,
		gemsWidth = 120,
		gap = 8,
		icon = 24, -- coin / gem glyphs
		iconInset = 10, -- glyph's left edge from the panel's left edge
		iconNudge = -1, -- glyph's vertical offset from the panel's middle
		textGap = 8, -- the amount's left edge this far right of the glyph
		plus = 32, -- Gems' pink "+" (square), `plusInset` px from the panel's right edge
		plusInset = 4,
		plusGap = 4, -- between the Gems amount and the "+"
		-- Roblox's default chat window (top-left, under the top bar) in screen px: `chatWidth`, or
		-- `chatFraction` of the screen on narrow ones. Cash's left edge (outline included) stays
		-- right of it: on windows under ~900 px wide the HUD scales down a little (HudScale).
		chatWidth = 230,
		chatFraction = 0.3,
	},

	-- Upgrades / Daily / Almanac tiles, top-right, left to right, `gap` px apart as drawn (from one
	-- tile's shadow to the next tile's outline). The red dot is a small diamond kept inside the tile
	-- (its center `dotInset` px from the top-right corner); the glyph sits left of center so the
	-- glyph, its outline and its shadow end before the dot.
	tiles = {
		width = 52,
		gap = 8,
		glyph = 20,
		glyphShift = -8,
		dot = 8,
		dotInset = 9,
	},

	-- Right column under the tiles, top to bottom: weather countdown, Instant Weather, Starter
	-- Bundle, bag count, `gap` px apart as drawn (shadow to outline; the first row `gap` under the
	-- tiles' shadows). Weather, Instant Weather and the bundle share `width`.
	column = {
		gap = 8,
		width = 200,
		-- Weather countdown chip (hub; every zone from 5 min before an event until it ends): text
		-- `textX` px in from the left, `textRight` from the right, `textY` from top and bottom.
		weather = { height = 32, textX = 12, textRight = 6, textY = 3, text = 17 },
		instantHeight = 50,
		bundleHeight = 54,
		bagWidth = 130,
		bagHeight = 44,
		bagGlyph = 24,
		bagGlyphInset = 14, -- the bag's left edge from the chip's left edge
		-- Count label ("12/200"): `x` px right of the glyph, `right` px from the chip's right edge,
		-- `y` px from its top and bottom, text up to `text` px.
		bagText = { x = 8, right = 8, y = 7, text = 20 },
		height = 240, -- the column frame (rows stack from its top; nothing is clipped)
		-- Two-line buttons (Instant Weather, Starter Bundle): { y, height, text size }, inset `lineInset`.
		lineInset = 6,
		line1 = { y = 4, height = 18, text = 15 },
		line2 = { y = 24, height = 15, text = 13 },
	},

	-- SHOP: the biggest button in the hub. At the plot it is the WATER button's size, beside it.
	-- Mid-right (touch screens; at the plot also narrow windows) SHOP and WATER sit `column.gap`
	-- under the right column at its tallest in that zone, and the hub SHOP must still clear the
	-- jump button on the smallest phones (800x360): hubHeight <= 84.
	shop = {
		hubWidth = 230,
		hubHeight = 80,
		hubText = 36,
		plotText = 22,
	},

	-- WATER and SHOP at the plot (same size), always side by side, Water on the left. Desktop:
	-- bottom-right when that clears the egg tray by `trayClearance`, else (a narrow window) mid-right
	-- like touch screens, where the jump button owns the corner.
	plotButtons = {
		width = 132,
		height = 64,
		gap = 8,
		glyph = 28,
		glyphInset = 10, -- the drop's left edge from the button's left edge
		trayClearance = 11, -- frame edge to the tray's shadow: 8 px as drawn + WATER's 3 px outline
		ringWidth = 5, -- the drain ring along the Water button's edge
		-- WATER's two lines ("WATER" / "· 2x 30s"), right of the glyph: x = glyphInset + glyph + `textGap`.
		textGap = 8,
		textRight = 6,
		line1 = { y = 9, height = 24, text = 20 },
		line2 = { y = 33, height = 20, text = 15 },
	},

	-- Egg tray (plot, bottom center): owned eggs + one "next egg" tile, HATCH on the right.
	-- Tiles size to content: egg art, a name, a count (or price) badge in the corner. A tile is at
	-- least `tileWidth` and grows with its text, estimated in em of GothamBlack capitals (Roblox
	-- draws it with Montserrat Black): `charWidth` per character, `wideChars` for the wide ones,
	-- `spaceWidth` per space, `emojiWidth` per emoji; a little generous, so text never has to
	-- shrink. An owned egg's name may wrap at its spaces ("STARTER" / "GEM"), so only its longest
	-- word sets the width; the next egg tile reads "SWAMP" / "AT THE" / "EGG SHOP". That keeps any
	-- two owned eggs plus the next egg tile inside `width` without scrolling; more eggs scroll.
	tray = {
		width = 424,
		height = 158,
		bottom = 12,
		tileWidth = 78,
		charWidth = 0.78,
		wideChars = { W = 1.21, M = 0.95 },
		spaceWidth = 0.3,
		emojiWidth = 1.3,
		tileHeight = 116,
		tileGap = 8,
		art = 64,
		artY = 2,
		lift = 8, -- the picked egg rises this much
		badgeWidth = 32, -- "x3" (at least; badges grow with their text)
		nextBadgeWidth = 46, -- "$500"
		badgeHeight = 20,
		badgeInset = 3,
		badgeText = 14,
		labelInset = 4, -- name: from the tile's sides and bottom
		labelHeight = 34, -- two lines of `labelText`, bottom-aligned
		labelText = 14,
		-- Next egg tile: one name line (`nextNameHeight`, its bottom `nextNameBottom` above the tile's
		-- bottom) over the two "AT THE" / "EGG SHOP" lines (`nextShopHeight`, `labelInset` up).
		nextNameBottom = 34,
		nextNameHeight = 18,
		nextShopHeight = 30,
		nextShopText = 13, -- >= 7 px on the narrowest phone (scale ~0.56)
		nextShopInset = 3,
		hatchWidth = 102,
		hatchInset = 10, -- from the tray's right edge, lined up with the 2x Luck badge
		hatchGlyph = 34,
		hatchGlyphY = 14,
		hatchLine1 = { y = 54, height = 20, text = 18 }, -- "HATCH 3"
		hatchLine2 = { y = 76, height = 16, text = 14 }, -- "TAP!" / "GROWING"
		chatWidth = 215, -- the chat window at its smallest (WidthScale 0.5), plus margin
	},
	-- Next Up's bottom edge above the screen bottom (clear of the tray's tab). It slides left when
	-- the mid-right buttons (a narrow window) would reach over it.
	nextUpBottom = 202,
	nextUpWidth = 400,
	nextUpHeight = 32,

	-- Vector glyphs (UI/Glyphs.lua): ink outline and the boxy hard shadow (Theme.shadow), in design
	-- px. The shadow is faded as one layer (a CanvasGroup) like C.shadow, so overlapping shapes
	-- never show seams.
	glyph = {
		stroke = 3,
		shadow = 4,
		shadowTransparency = 0.2,
	},
}
