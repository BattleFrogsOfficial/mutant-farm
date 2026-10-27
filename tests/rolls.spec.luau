return function(t)
	local Rolls = t.require("src/shared/Rolls")
	local Rng = t.require("src/shared/Rng")
	local Eggs = t.require("src/shared/Config/Eggs")
	local Rarities = t.require("src/shared/Config/Rarities")

	local function sum(weights)
		local total = 0
		for _, w in weights do
			total += w
		end
		return total
	end

	return {
		["every tier's odds sum to 100"] = function()
			for _, id in Eggs.order do
				t.near(sum(Eggs.tiers[id].odds), 100, 1e-9, id)
			end
		end,
		["luck 1 leaves odds unchanged"] = function()
			local w = Rolls.rarityWeights("Starter", 1)
			for _, rarity in Rarities.order do
				t.near(w[rarity], Eggs.tiers.Starter.odds[rarity], 1e-9, rarity)
			end
		end,
		["max luck renormalizes instead of overflowing"] = function()
			for _, id in Eggs.order do
				local w = Rolls.rarityWeights(id, 6)
				t.near(sum(w), 100, 1e-9, id)
				t.ok(w.Common > 0, id .. " Common went non-positive")
			end
			-- Cosmic at 6x: non-common 45 * 6 = 270, total 325
			t.near(Rolls.rarityWeights("Cosmic", 6).Common, 55 / 325 * 100, 1e-9)
		end,
		["luck is capped at 6x"] = function()
			t.eq(Rolls.rarityWeights("Lab", 50), Rolls.rarityWeights("Lab", 6))
			t.eq(Rolls.clampLuck(0.2), 1)
		end,
		["rarity roll matches table over many rolls"] = function()
			local r = Rng.new(11)
			local n, common = 50_000, 0
			for _ = 1, n do
				if Rolls.rollRarity(r, "Starter", 1) == "Common" then
					common += 1
				end
			end
			t.near(common / n, 0.80, 0.01)
		end,
		["10 rolls give the documented per-egg mutation odds"] = function()
			local expected = { Shiny = 0.14, Golden = 0.058, Radioactive = 0.0247, Glitched = 0.008, Cosmic = 0.001 }
			for id, p in expected do
				local perEgg = 1 - (1 - Rolls.mutationChance(id, 1)) ^ 10
				t.near(perEgg, p, 0.001, id)
			end
		end,
		["mutation never repeats on one mutant"] = function()
			local r = Rng.new(5)
			local have = {}
			for _ = 1, 2000 do
				for _, id in Rolls.rollMutations(r, have, 6, 0.5) do
					t.ok(not table.find(have, id), "duplicate " .. id)
					table.insert(have, id)
				end
			end
		end,
		["sizes stay within 0.8x to 3x and weights sum to 100"] = function()
			t.near(sum(Rolls.sizeWeights(1)), 100, 1e-9)
			t.near(sum(Rolls.sizeWeights(6)), 100, 1e-9)
			local r = Rng.new(9)
			local titans = 0
			for _ = 1, 40_000 do
				local s = Rolls.rollSize(r, 1)
				t.ok(s >= 0.8 and s <= 3, "size out of range " .. s)
				if s == 3 then
					titans += 1
				end
			end
			t.near(titans / 40_000, 0.005, 0.0015)
		end,
	}
end
