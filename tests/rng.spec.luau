return function(t)
	local Rng = t.require("src/shared/Rng")
	return {
		["matches reference mulberry32"] = function()
			local r = Rng.new(1)
			t.near(r:next(), 0.6270739405881613, 1e-15)
			t.near(r:next(), 0.002735721180215478, 1e-15)
		end,
		["same seed, same sequence"] = function()
			local a, b = Rng.new(42), Rng.new(42)
			for _ = 1, 100 do
				t.eq(a:next(), b:next())
			end
		end,
		["stays in [0, 1)"] = function()
			local r = Rng.new(7)
			for _ = 1, 10_000 do
				local x = r:next()
				t.ok(x >= 0 and x < 1, "out of range: " .. x)
			end
		end,
		["weighted pick follows weights"] = function()
			local r = Rng.new(3)
			local counts = { a = 0, b = 0 }
			for _ = 1, 20_000 do
				local k = r:weighted({ "a", "b" }, { a = 3, b = 1 })
				counts[k] += 1
			end
			t.near(counts.a / 20_000, 0.75, 0.02)
		end,
	}
end
