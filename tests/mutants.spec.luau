return function(t)
	local Mutants = t.require("src/shared/Config/Mutants")
	local Eggs = t.require("src/shared/Config/Eggs")
	local Rarities = t.require("src/shared/Config/Rarities")

	local VALID = {
		body = { blob = true, tall = true, flat = true, spiky = true, pear = true, worm = true, puff = true },
		pattern = { plain = true, spots = true, stripes = true, belly = true },
		eyeStyle = { normal = true, stalk = true, sleepy = true, angry = true },
		mouth = { smile = true, fangs = true, tooth = true, wide = true, tongue = true, none = true },
		accessory = {
			none = true,
			antennae = true,
			horns = true,
			ears = true,
			leaf = true,
			goggles = true,
			mohawk = true,
			wings = true,
			halo = true,
			crown = true,
			witchHat = true,
			stem = true,
		},
	}

	return {
		["there are exactly 400 regular species, plus 2 per rarity for each limited egg"] = function()
			local regular, limited = 0, {}
			for _, e in Mutants.species do
				if Eggs.tiers[e.tier] and Eggs.tiers[e.tier].limited then
					limited[e.tier] = (limited[e.tier] or 0) + 1
				else
					regular += 1
				end
			end
			t.eq(regular, 400)
			for _, id in Eggs.limitedOrder do
				t.eq(limited[id], 10, id .. " species")
				for _, rarity in Rarities.order do
					t.eq(#Mutants.buckets[id][rarity], 2, id .. " " .. rarity)
				end
			end
		end,
		["every tier and rarity has species to hatch"] = function()
			for _, tier in Eggs.order do
				for _, rarity in Rarities.order do
					local bucket = Mutants.buckets[tier] and Mutants.buckets[tier][rarity]
					t.ok(bucket and #bucket > 0, tier .. "/" .. rarity .. " is empty")
				end
			end
		end,
		["every species uses valid looks and unique names"] = function()
			local names = {}
			for id, e in Mutants.species do
				for field, allowed in VALID do
					t.ok(allowed[e[field]], id .. " has bad " .. field .. ": " .. tostring(e[field]))
				end
				t.ok(e.eyes >= 1 and e.eyes <= 4, id .. " eyes")
				t.ok(e.color:match("^#%x%x%x%x%x%x$") and e.accent:match("^#%x%x%x%x%x%x$"), id .. " colors")
				t.ok(not names[e.name], "duplicate name " .. e.name)
				names[e.name] = true
				t.eq(e.id, id)
			end
		end,
	}
end
