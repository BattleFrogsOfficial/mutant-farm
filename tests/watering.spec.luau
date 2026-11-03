-- Watering rules (shared/Watering.lua): the growth circle's offers (3x-10x, lower likelier),
-- the tap cooldown, and where the circle shows up next.
return function(t)
	local Watering = t.require("src/shared/Watering")
	local GameConfig = t.require("src/shared/Config/Game")
	return {
		["offers run 3x to 10x, lower likelier, odds sum to 1"] = function()
			local odds = Watering.odds()
			local sum, last = 0, math.huge
			for mult = 3, 10 do
				t.ok(odds[mult] and odds[mult] > 0, mult .. "x is offered")
				t.ok(odds[mult] <= last, mult .. "x is no likelier than " .. (mult - 1) .. "x")
				last = odds[mult]
				sum += odds[mult]
			end
			t.near(sum, 1, 1e-9)
			t.eq(odds[2], nil)
			t.eq(odds[11], nil)
			t.near(Watering.averageOffer(), 4.94, 1e-9)
		end,
		["offerFor walks the weights"] = function()
			t.eq(Watering.offerFor(0), 3)
			t.eq(Watering.offerFor(0.2999), 3)
			t.eq(Watering.offerFor(0.3), 4)
			t.eq(Watering.offerFor(0.9999), 10)
			-- a seeded sweep lands near the configured odds
			local counts = {}
			local n = 20000
			for i = 0, n - 1 do
				local m = Watering.offerFor((i + 0.5) / n)
				counts[m] = (counts[m] or 0) + 1
			end
			for mult, p in Watering.odds() do
				t.near(counts[mult] / n, p, 1e-3)
			end
		end,
		["a tap waits for the last boost to run out (a little latency is fine)"] = function()
			local grace = GameConfig.water.tapGrace
			t.ok(Watering.canTap(100, 0), "no boost yet")
			t.ok(not Watering.canTap(100, 104), "boost still running")
			t.ok(Watering.canTap(104 - grace, 104), "just inside the grace")
			t.ok(not Watering.canTap(104 - grace - 0.05, 104), "too early")
			t.eq(Watering.boostEnd(100), 100 + GameConfig.water.tapSeconds)
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
