return function(t)
	local HudScale = t.require("src/shared/HudScale")
	return {
		["HUD scale: shorter edge / 540, capped 1.25 (mouse) and 1.0 (touch)"] = function()
			-- 1663x726 window: 668 px below the top bar -> 1.237
			t.near(HudScale.of(1663, 668, false), 668 / 540, 1e-9)
			t.eq(HudScale.of(1920, 1022, false), 1.25)
			t.eq(HudScale.of(1920, 1022, true), 1.0)
			t.near(HudScale.of(844, 332, true), 332 / 540, 1e-9) -- phone: height is the short edge
			t.eq(HudScale.of(200, 100, false), 0.5) -- floor
			t.eq(HudScale.of(700, 2000, false), 1.25) -- portrait: width is the short edge
			t.near(HudScale.of(500, 2000, true), 500 / 540, 1e-9)
		end,
	}
end
