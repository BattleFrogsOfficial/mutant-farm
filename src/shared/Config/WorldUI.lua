--!strict
-- Layout numbers for the UI drawn in the world on your own plot (client only): the soil marker
-- on each empty or buyable patch (UI/SoilMarker) and the timer over each growing egg
-- (UI/SlotTimer). Tuning the look never edits PlotController or the builders.

return {
	-- Soil marker: a SurfaceGui on the patch's Top face. Its canvas is the patch (3.6 studs) at
	-- pixelsPerStud, so every px number below is canvas px (144 px across at 40 px/stud).
	soil = {
		pixelsPerStud = 40,
		-- The tile as a fraction of the patch: a small "+" on an empty patch, a wider one with the
		-- price on the patch you can buy next.
		plusSize = { 0.38, 0.38 },
		priceSize = { 0.9, 0.38 },
		outline = 4, -- ink outline (canvas px; ~2 px on a phone)
		shadow = 6, -- hard shadow offset (canvas px)
		bevel = 4, -- light strip along the tile's top edge
		-- Text inset in canvas px: none for the "+" (the glyph sits small in its line
		-- box), some for the price.
		textInset = { plus = 0, price = 7 },
		-- Pulse during the tutorial's plant steps: scale 1 .. 1 + pulseAmount, pulseSpeed rad/s.
		pulseAmount = 0.1,
		pulseSpeed = 3.2,
		-- The Top face's canvas reads upside down from the gate side, where players walk in.
		rotation = 180,
		-- Preview only: roughly how wide a patch is on a phone (844x390) at the default camera
		-- distance (~15 studs), in screen px. The UI preview draws the marker at this size.
		phonePatchPx = 66,
	},
	-- Timer over a growing egg on your own plot: a BillboardGui of fixed pixel size (the same on
	-- every screen). The "2x" chip sits above the bar's right end while the plot is watered.
	timer = {
		width = 84,
		barHeight = 22,
		chipWidth = 32,
		chipHeight = 20,
		chipGap = 3, -- between the chip and the bar
		outline = 2,
		studsAbove = 4.2, -- the bar's height above the soil
		maxDistance = 45,
		chipText = "2x",
	},
}
