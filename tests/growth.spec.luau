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
			t.eq(Growth.speed(0, true), 2)
			t.near(Growth.speed(5, true), 3, 1e-9)
		end,
		["dry growth is real time x speed"] = function()
			t.eq(Growth.advance(0, 100, 160, Growth.DRY, 1), 60)
			t.eq(Growth.advance(10, 100, 130, Growth.DRY, 2), 70)
			t.eq(Growth.waterRate(Growth.DRY, 0), 1)
		end,
		["the water pad grows 2x while you stand on it"] = function()
			local pad = Growth.water(0, 1, true)
			t.eq(Growth.advance(0, 100, 160, pad, 1), 120)
			-- the pad and the 2x pass stack to 4x
			t.eq(Growth.advance(0, 100, 110, pad, 2), 40)
			t.eq(Growth.waterRate(pad, 100), 2)
		end,
		["a tapped boost runs at its multiplier only inside its window"] = function()
			-- 7x until 105: 5 s at 7x + 55 s at 1x
			local boost = Growth.water(105, 7, false)
			t.eq(Growth.advance(0, 100, 160, boost, 1), 90)
			t.eq(Growth.waterRate(boost, 104.9), 7)
			t.eq(Growth.waterRate(boost, 105), 1)
			-- the boost and the pass multiply
			t.eq(Growth.advance(0, 100, 105, boost, 2), 70)
		end,
		["boost and pad: the higher one applies, they don't multiply"] = function()
			-- 5x boost while on the pad: 5 s at 5x, then the pad's 2x
			t.eq(Growth.advance(0, 100, 115, Growth.water(105, 5, true), 1), 25 + 20)
			-- a boost below the pad's multiplier never slows you down
			t.eq(Growth.advance(0, 100, 110, Growth.water(200, 1.5, true), 1), 20)
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
