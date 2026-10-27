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
		["unwatered growth is real time x speed"] = function()
			t.eq(Growth.advance(0, 100, 160, 0, 1), 60)
			t.eq(Growth.advance(10, 100, 130, 0, 2), 70)
		end,
		["watering doubles only inside the window"] = function()
			-- watered until 115: 15s at 2x + 45s at 1x
			t.eq(Growth.advance(0, 100, 160, 115, 1), 75)
			-- window fully covers the span
			t.eq(Growth.advance(0, 100, 110, 200, 1), 20)
			-- watering and 2x pass stack to 4x
			t.eq(Growth.advance(0, 100, 110, 200, 2), 40)
		end,
		["advancing in pieces equals advancing once"] = function()
			local once = Growth.advance(0, 0, 100, 40, 1.5)
			local pieces =
				Growth.advance(Growth.advance(Growth.advance(0, 0, 25, 40, 1.5), 25, 70, 40, 1.5), 70, 100, 40, 1.5)
			t.near(pieces, once, 1e-9)
		end,
		["seconds remaining inverts advance"] = function()
			for _, case in { { 0, 60, 0, 1 }, { 10, 300, 20, 1 }, { 0, 60, 100, 2 }, { 50, 900, 5, 1.3 } } do
				local growth, required, wateredFor, speed = case[1], case[2], case[3], case[4]
				local now = 1000
				local wateredUntil = now + wateredFor
				local secs = Growth.secondsRemaining(growth, required, now, wateredUntil, speed)
				t.near(Growth.advance(growth, now, now + secs, wateredUntil, speed), required, 1e-6)
			end
			t.eq(Growth.secondsRemaining(70, 60, 0, 0, 1), 0)
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
