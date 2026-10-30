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
			-- Never a canvas narrower than 900: 4:3 and portrait windows scale by their width.
			t.near(HudScale.of(960, 662, false), 960 / 900, 1e-9) -- 960x720 window
			t.near(HudScale.of(1024, 710, false), 1024 / 900, 1e-9) -- 1024x768 window
			t.near(HudScale.of(1000, 2000, false), 1000 / 900, 1e-9)
		end,
		["HUD scale: Cash stays clear of the top-left chat on narrow windows"] = function()
			-- Cash's drawn left edge is 150 + 66 + 3 = 219 design px left of the middle.
			t.near(HudScale.of(800, 542, false), (400 - 230) / 219, 1e-9) -- 800x600 window
			t.near(HudScale.of(700, 2000, false), (350 - 210) / 219, 1e-9) -- chat at 30% of 700
			t.eq(HudScale.of(500, 2000, true), 0.5) -- floor
			-- Phones keep the shorter-edge scale (the chat bound is looser there).
			t.near(HudScale.of(667, 317, true), 317 / 540, 1e-9)
			t.near(HudScale.of(800, 302, true), 302 / 540, 1e-9)
			for _, wh in { { 800, 542 }, { 667, 317 }, { 800, 302 }, { 960, 662 }, { 1280, 662 } } do
				local w, h = wh[1], wh[2]
				local s = HudScale.of(w, h, false)
				t.ok(
					w / 2 - 219 * s >= math.min(230, w * 0.3) - 1e-9,
					string.format("Cash clear of chat at %dx%d", w, h)
				)
			end
		end,
	}
end
