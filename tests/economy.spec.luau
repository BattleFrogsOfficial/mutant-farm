return function(t)
	local Valuation = t.require("src/shared/Valuation")
	local Costs = t.require("src/shared/Costs")
	local GameConfig = t.require("src/shared/Config/Game")
	return {
		["Golden Legendary Toxic is about 160M"] = function()
			local v =
				Valuation.sellValue({ tier = "Toxic", rarity = "Legendary", mutations = { "Golden" }, size = 1 }, 1)
			t.eq(v, 162_500_000)
		end,
		["mutations multiply, ceiling is x250,000"] = function()
			t.eq(Valuation.mutationMultiplier({}), 1)
			t.eq(Valuation.mutationMultiplier({ "Shiny", "Golden" }), 10)
			t.eq(Valuation.mutationMultiplier({ "Shiny", "Golden", "Radioactive", "Glitched", "Cosmic" }), 250_000)
		end,
		["base value ignores mutations and size"] = function()
			t.eq(Valuation.baseValue({ tier = "Swamp", rarity = "Rare", mutations = { "Cosmic" }, size = 3 }), 9_000)
		end,
		["cash multiplier: +50% per rebirth, VIP multiplies"] = function()
			t.eq(Valuation.cashMultiplier(0, false), 1)
			t.eq(Valuation.cashMultiplier(4, false), 3)
			t.eq(Valuation.cashMultiplier(10, false), 6)
			t.eq(Valuation.cashMultiplier(4, true), 4.5)
			t.near(Valuation.cashMultiplier(0, false, 0.1), 1.1, 1e-9)
		end,
		["pen income: 0.05% of base value per minute x rebirth multiplier, size and mutations ignored"] = function()
			local m = { tier = "Toxic", rarity = "Rare", mutations = { "Golden" }, size = 1.5 }
			-- base 130K x Rare 10 = 1.3M; x 0.0005 = 650/min; x2 rebirth multiplier (2 rebirths)
			t.near(Valuation.penIncome(m, Valuation.rebirthMultiplier(2), GameConfig.penIncomePerMinute), 1_300, 1e-6)
			t.near(Valuation.penIncome(m, 1, GameConfig.penIncomePerMinuteOffline), 130, 1e-6)
		end,
		["a kept mutant pays back its sell value in ~33 hours online"] = function()
			for _, rebirths in { 0, 3 } do
				local m = { tier = "Swamp", rarity = "Epic", mutations = {}, size = 1 }
				local mult = Valuation.rebirthMultiplier(rebirths)
				local perMinute = Valuation.penIncome(m, mult, GameConfig.penIncomePerMinute)
				local hours = Valuation.sellValue(m, mult) / perMinute / 60
				t.near(hours, 33.3, 0.1, "payback hours at rebirth " .. rebirths)
			end
		end,
		["slot costs start at 200 and grow 1.5x"] = function()
			t.eq(Costs.slot(6, 0), nil)
			t.eq(Costs.slot(7, 0), 200)
			t.eq(Costs.slot(8, 0), 300)
			t.eq(Costs.slot(41, 0), nil)
			t.eq(Costs.slot(7, 1), 300)
			t.eq(Costs.slot(7, 4), 600)
		end,
		["upgrade costs triple and stop at level 5"] = function()
			t.eq(Costs.upgrade("growthSpeed", 0, 0), 2000)
			t.eq(Costs.upgrade("growthSpeed", 1, 0), 6000)
			t.eq(Costs.upgrade("mutationOdds", 5, 0), nil)
		end,
		["rebirth 1 costs 700K, rebirth N = 700K x 4.5^(N-1)"] = function()
			t.eq(Costs.rebirth(0), 700_000)
			t.eq(Costs.rebirth(1), 3_150_000)
			t.eq(Costs.rebirth(2), 14_175_000)
			t.eq(Costs.rebirth(3), 63_787_500)
			for n = 1, 12 do
				t.near(Costs.rebirth(n - 1), 700_000 * 4.5 ^ (n - 1), 1)
			end
		end,
		["rebirth costs rise every time"] = function()
			local last = 0
			for r = 0, 15 do
				local c = Costs.rebirth(r)
				t.ok(c > last, "rebirth " .. r .. " not increasing")
				last = c
			end
		end,
		["sanity cap covers the best possible sale"] = function()
			local best = Valuation.sellValue({
				tier = "Swamp",
				rarity = "Legendary",
				mutations = { "Shiny", "Golden", "Radioactive", "Glitched", "Cosmic" },
				size = 3,
			}, 1)
			t.ok(best <= Valuation.maxSingleSale(0, 1))
			t.ok(Valuation.maxSingleSale(0, 1) < Valuation.maxSingleSale(1, 1.5))
		end,
	}
end
