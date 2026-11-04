--!strict
-- The tutorial card (UI in client/UI/Hud's tutorial card, steps in shared/Onboarding.tutorialStep,
-- TutorialController picks the step and the target). One boxy card, bottom-center: above the egg
-- tray on your plot, above SHOP's row in the hub. Navy with a gold stripe on the left and the star
-- glyph; the step title in CAPS, one instruction line, "3 / 9" with pips. When a step completes
-- the glyph turns into a check for `checkSeconds`, then the next step. It hides while a panel is
-- open (the whole HUD does) and, once the tutorial is done (profile.tutorialDone), Next Up takes
-- the same slot in the same chrome. Every step ends on the real event.

return {
	card = {
		width = 420,
		height = 50,
		stripe = 6, -- the gold stripe on the left
		glyph = 20, -- the star / check glyph
		title = { y = 4, height = 22, text = 18 },
		line = { y = 24, height = 18, text = 14, priceText = 16 }, -- 16 when the line shows a price
		-- The progress strip along the bottom: one segment per step (done gold, current cream).
		strip = { y = 44, height = 3, gap = 2 },
		countWidth = 44, -- "3 / 9" at 16 px, top right
		-- In the hub the card sits above SHOP's row: its bottom edge this far above the screen
		-- bottom (SHOP 80 + shadow 4 + the edge margin + 8 px as drawn + outlines).
		hubBottom = 108,
	},
	appearAfter = 1, -- seconds after spawning before the first step's card shows
	checkSeconds = 0.7, -- the check animation on a completed step
	weatherSeconds = 5, -- the solo Solar Flare's card ("WEATHER!") when it hits
	pollSeconds = 0.1, -- how often the controller checks for a completed step (well inside 0.3 s)
	-- The target's slow gold outline (a Highlight, outline only) and the guide beam.
	outline = { period = 1.6, minTransparency = 0.1, maxTransparency = 0.7 },

	-- Steps in order (Onboarding.tutorialStep's ids). `line` may hold one %s (a price).
	steps = {
		{ id = "hatch", title = "TAP HATCH", line = "Your first egg is ready" },
		{ id = "sell", title = "SELL IT", line = "Walk onto the Sell pad in the market" },
		{
			id = "buy",
			title = "BUY 2 EGGS",
			line = "Tap BUY on your egg tray",
			lineShop = "At the Egg Shop in the market",
		},
		{ id = "plant", title = "PLANT THEM", line = "Tap your empty soil patches" },
		{ id = "water", title = "STAND ON THE WATER PAD", line = "2x growth: watch the chip on your egg" },
		{ id = "hatch2", title = "HATCH", line = "Tap HATCH when your eggs are ready" },
		{
			id = "patch",
			title = "BUY A SOIL PATCH",
			line = "Tap the %s patch on your farm",
			lineSave = "Earn %s for a new patch",
		},
		{ id = "swamp", title = "GET A SWAMP EGG", line = "At the Egg Shop in the market" },
		{ id = "almanac", title = "OPEN THE ALMANAC", line = "Tap the book: every mutant you find" },
	},
	-- A profile without the pre-planted egg (the opening switched off) starts here, as step 1.
	plantFirst = { title = "PLANT YOUR EGG", line = "Tap a soil patch to plant it" },
	weather = { title = "WEATHER!", line = "Bonus mutation roll on your eggs" },
	nextUpTitle = "NEXT UP",
}
