-- Every egg tier must be fully playable the moment a rebirth unlocks it: real prices, grow
-- times, values, odds that sum to 100, a design, and species for every rarity.
return function(t)
	local Eggs = t.require("src/shared/Config/Eggs")
	local Rarities = t.require("src/shared/Config/Rarities")
	local Mutants = t.require("src/shared/Config/Mutants")
	local Costs = t.require("src/shared/Costs")
	return {
		["every tier has price, grow time, value, odds and a design"] = function()
			t.eq(#Eggs.order, 6)
			for _, id in Eggs.order do
				local tier = Eggs.tiers[id]
				t.ok(tier.cost > 0 and tier.growTime > 0 and tier.baseValue > 0, id .. " numbers")
				t.ok(tier.design and tier.design.pattern, id .. " design")
				local sum = 0
				for _, rarity in Rarities.order do
					sum += tier.odds[rarity] or 0
				end
				t.near(sum, 100, 1e-6)
			end
		end,
		["every tier x rarity has species to hatch"] = function()
			for _, id in Eggs.order do
				for _, rarity in Rarities.order do
					local bucket = Mutants.buckets[id] and Mutants.buckets[id][rarity]
					t.ok(bucket ~= nil and #bucket > 0, id .. " " .. rarity .. " has species")
				end
			end
		end,
		["tiers unlock in rebirth order and get pricier"] = function()
			for i = 2, #Eggs.order do
				local a, b = Eggs.tiers[Eggs.order[i - 1]], Eggs.tiers[Eggs.order[i]]
				t.ok(b.unlockRebirth >= a.unlockRebirth, "unlock order")
				t.ok(b.cost > a.cost and b.baseValue > a.baseValue, "price/value order")
			end
		end,
		["skip timer: 5 Gems per started 10 minutes"] = function()
			t.eq(Costs.skip(0, 5), 0)
			t.eq(Costs.skip(1, 5), 5)
			t.eq(Costs.skip(600, 5), 5)
			t.eq(Costs.skip(601, 5), 10)
			t.eq(Costs.skip(8 * 3600, 5), 240)
		end,
	}
end
