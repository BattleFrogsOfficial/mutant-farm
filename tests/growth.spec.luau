return function(t)
	local Growth = t.require("src/shared/Growth")
	return {
		["required time scales with rarity"] = function()
			t.eq(Growth.requiredSeconds("Starter", "Common"), 60)
			t.eq(Growth.requiredSeconds("Toxic", "Legendary"), 3 * 3600)
			t.eq(Growth.requiredSeconds("Swamp", "Uncommon"), 375)
		end,
		["speed stacks pass and upgrade"] = function()
			t.eq(Growth.speed(0, false), 1)
			t.eq(Growth.speed(0, true), 1.5) -- the Growth Speed pass (Passes.GrowthSpeed2x.multiplier)
			t.near(Growth.speed(5, true), 2.25, 1e-9)
		end,
		["dry growth is real time x speed"] = function()
			t.eq(Growth.advance(0, 100, 160, Growth.DRY, 1), 60)
			t.eq(Growth.advance(10, 100, 130, Growth.DRY, 2), 70)
			t.eq(Growth.waterRate(Growth.DRY, 0), 1)
		end,
		["the water pad grows 2x while you stand on it"] = function()
			local pad = Growth.water(0, 1, true)
			t.eq(Growth.advance(0, 100, 160, pad, 1), 120)
			-- the pad and the speed multiplier stack (a speed of 2 -> 4x)
			t.eq(Growth.advance(0, 100, 110, pad, 2), 40)
			t.eq(Growth.waterRate(pad, 100), 2)
		end,
		["a tapped boost runs at its multiplier only inside its window, then back to the pad's 2x"] = function()
			-- 7x until 105 on the pad: 5 s at 7x + 55 s at 2x
			local boost = Growth.water(105, 7, true)
			t.eq(Growth.advance(0, 100, 160, boost, 1), 35 + 110)
			t.eq(Growth.waterRate(boost, 104.9), 7)
			t.eq(Growth.waterRate(boost, 105), 2)
			-- the boost and the pass multiply
			t.eq(Growth.advance(0, 100, 105, boost, 2), 70)
		end,
		["off the pad the circle has no effect: 1x, even inside a boost's window"] = function()
			local off = Growth.water(105, 7, false)
			t.eq(Growth.advance(0, 100, 160, off, 1), 60)
			t.eq(Growth.waterRate(off, 101), 1)
			t.eq(Growth.totalSpeed(off, 101, 1.5), 1.5, "the pass alone")
			t.eq(Growth.totalSpeed(Growth.water(105, 7, true), 101, 1.5), 10.5, "boost x pass, on the pad")
			t.eq(Growth.totalSpeed(Growth.water(105, 7, true), 101, 1.5), 10.5, "boost x pass")
			t.eq(Growth.totalSpeed(Growth.water(0, 1, true), 101, 1.5), 3, "pad x pass")
		end,
		["boost and pad: the higher one applies, they don't multiply"] = function()
			-- 5x boost while on the pad: 5 s at 5x, then the pad's 2x
			t.eq(Growth.advance(0, 100, 115, Growth.water(105, 5, true), 1), 25 + 20)
			-- a boost below the pad's multiplier never slows you down
			t.eq(Growth.advance(0, 100, 110, Growth.water(200, 1.5, true), 1), 20)
		end,
		["timers show time left at 1x: a speed change never jumps them, they count at the speed"] = function()
			local required = 300
			local g = Growth.advance(0, 0, 100, Growth.water(0, 1, false), 1) -- 100 s dry
			local before = Growth.displayRemaining(g, required)
			-- Stepping onto the pad (and a 1.5x pass) at the same instant: same progress, same text.
			local onPad = Growth.water(0, 1, true)
			local after = Growth.displayRemaining(Growth.advance(g, 100, 100, onPad, 1.5), required)
			t.eq(before, 200)
			t.eq(after, before, "no jump on a speed change")
			-- Then it counts down at the total speed (2 x 1.5 = 3 s per second).
			local later = Growth.displayRemaining(Growth.advance(g, 100, 101, onPad, 1.5), required)
			t.near(before - later, Growth.totalSpeed(onPad, 100, 1.5), 1e-9)
			t.eq(Growth.displayRemaining(400, required), 0)
		end,
		["advancing in pieces equals advancing once"] = function()
			local w = Growth.water(40, 6, true)
			local once = Growth.advance(0, 0, 100, w, 1.5)
			local pieces =
				Growth.advance(Growth.advance(Growth.advance(0, 0, 25, w, 1.5), 25, 70, w, 1.5), 70, 100, w, 1.5)
			t.near(pieces, once, 1e-9)
		end,
		["seconds remaining inverts advance"] = function()
			local cases = {
				{ 0, 60, 0, 1, 1, false },
				{ 10, 300, 20, 3, 1, false },
				{ 0, 60, 100, 10, 2, false },
				{ 50, 900, 5, 4, 1.3, true },
				{ 0, 600, 3, 9, 1, true },
				{ 0, 600, 0, 1, 1, true },
			}
			for _, case in cases do
				local growth, required, boostFor, mult, speed, onPad = table.unpack(case)
				local now = 1000
				local w = Growth.water(now + boostFor, mult, onPad)
				local secs = Growth.secondsRemaining(growth, required, now, w, speed)
				t.near(Growth.advance(growth, now, now + secs, w, speed), required, 1e-6)
			end
			t.eq(Growth.secondsRemaining(70, 60, 0, Growth.DRY, 1), 0)
		end,
		["mutation rolls are spaced in tenths of the grow"] = function()
			t.eq(Growth.rollsCrossed(0, 60, 60), 10)
			t.eq(Growth.rollsCrossed(0, 5.9, 60), 0)
			t.eq(Growth.rollsCrossed(0, 6, 60), 1)
			t.eq(Growth.rollsCrossed(6, 30, 60), 4)
			t.eq(Growth.rollsCrossed(30, 500, 60), 5)
		end,
	}
end
