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
		},
	}

	return {
		["there are exactly 400 species"] = function()
			local n = 0
			for _ in Mutants.species do
				n += 1
			end
			t.eq(n, 400)
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
