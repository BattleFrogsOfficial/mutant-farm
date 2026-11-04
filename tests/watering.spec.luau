-- Watering rules (shared/Watering.lua): the growth circle's offers (2x-10x, lower likelier), the
-- boost, the vanish gap, and where the circle shows up next.
return function(t)
	local Watering = t.require("src/shared/Watering")
	local GameConfig = t.require("src/shared/Config/Game")
	return {
		["offers: 3x / 4x / 5x / 7x / 10x by weight 30 / 20 / 12 / 5 / 3, no 2x (the pad already is)"] = function()
			local odds = Watering.odds()
			local want = { [3] = 30 / 70, [4] = 20 / 70, [5] = 12 / 70, [7] = 5 / 70, [10] = 3 / 70 }
			local sum = 0
			for mult, p in want do
				t.near(odds[mult], p, 1e-9, mult .. "x")
				sum += odds[mult]
			end
			t.near(sum, 1, 1e-9)
			t.eq(odds[2], nil, "no 2x offer")
			t.near(Watering.averageOffer(), 295 / 70, 1e-9)
		end,
		["10,000 rolled offers average the table's 3.55x +- 0.05"] = function()
			local Rng = t.require("src/shared/Rng")
			local rng = Rng.new(4242)
			local total = 0
			for _ = 1, 10_000 do
				total += Watering.offerFor(rng:next())
			end
			t.near(total / 10_000, Watering.averageOffer(), 0.05)
		end,
		["offerFor walks the weights"] = function()
			t.eq(Watering.offerFor(0), 3)
			t.eq(Watering.offerFor(30 / 70 - 0.0001), 3)
			t.eq(Watering.offerFor(30 / 70 + 0.0001), 4)
			t.eq(Watering.offerFor(0.9999), 10)
		end,
		["after a boost the circle vanishes for 3-8 s; taps wait for it (a little latency is fine)"] = function()
			local w = GameConfig.water
			t.eq(w.boostSeconds, 5)
			t.eq(Watering.gapFor(0), w.gapMin)
			t.eq(Watering.gapFor(0.9999), w.gapMin + 0.9999 * (w.gapMax - w.gapMin))
			t.eq(w.gapMin, 3)
			t.eq(w.gapMax, 8)
			local boostEnd = Watering.boostEnd(100)
			t.eq(boostEnd, 105)
			local ready = Watering.readyAt(boostEnd, 0.5)
			t.eq(ready, 105 + 5.5)
			t.ok(Watering.circleShown(102, boostEnd, ready), "shown while the boost runs")
			t.ok(not Watering.circleShown(107, boostEnd, ready), "gone during the gap")
			t.ok(Watering.circleShown(ready, boostEnd, ready), "back after it")
			t.ok(not Watering.canTap(107, ready), "no tap during the gap")
			t.ok(Watering.canTap(ready - w.tapGrace, ready), "just inside the grace")
			t.ok(Watering.canTap(100, 0), "never tapped")
		end,
		["a perfect tapper's cycle on the pad: ~3.05x"] = function()
			t.near(Watering.cycleRate(2), 3.05, 0.01)
		end,
		["the circle never comes back on the same spot"] = function()
			for count = 2, 7 do
				for last = 1, count do
					local seen = {}
					for i = 0, 99 do
						local spot = Watering.nextSpot(last, count, i / 100)
						t.ok(spot >= 1 and spot <= count, "in range")
						t.ok(spot ~= last, "moves")
						seen[spot] = true
					end
					local n = 0
					for _ in seen do
						n += 1
					end
					t.eq(n, count - 1, "every other spot is reachable")
				end
			end
			t.ok(Watering.nextSpot(nil, 5, 0.99) == 5)
			t.eq(Watering.nextSpot(3, 1, 0.5), 1)
		end,
	}
end
