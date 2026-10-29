-- The egg tray's "next egg" tile (ShopRules.nextTrayEgg): the cheapest unlocked base tier the player
-- owns none of; gated tiers never appear.
return function(t)
	local ShopRules = t.require("src/shared/ShopRules")

	return {
		["a new player with only Starter eggs is shown Swamp"] = function()
			t.eq(ShopRules.nextTrayEgg({ Starter = 2 }, 0, 0), "Swamp")
		end,
		["no eggs at all: Starter"] = function()
			t.eq(ShopRules.nextTrayEgg({}, 0, 0), "Starter")
			t.eq(ShopRules.nextTrayEgg({ Starter = 0, Swamp = 0 }, 0, 0), "Starter", "a count of 0 isn't owned")
		end,
		["Lab only once $25K is earned"] = function()
			t.eq(ShopRules.nextTrayEgg({ Starter = 1, Swamp = 1 }, 0, 24_999), nil)
			t.eq(ShopRules.nextTrayEgg({ Starter = 1, Swamp = 1 }, 0, 25_000), "Lab")
		end,
		["rebirth-gated tiers never appear"] = function()
			t.eq(ShopRules.nextTrayEgg({ Starter = 1, Swamp = 1, Lab = 1 }, 0, 1e9), nil, "Toxic needs Rebirth 1")
			t.eq(ShopRules.nextTrayEgg({ Starter = 1, Swamp = 1, Lab = 1 }, 1, 0), "Toxic")
			t.eq(
				ShopRules.nextTrayEgg({ Starter = 1, Swamp = 1, Lab = 1, Toxic = 3 }, 2, 0),
				nil,
				"Void needs Rebirth 3"
			)
		end,
		["Gem and limited eggs neither count as owning the tier nor show as next"] = function()
			t.eq(ShopRules.nextTrayEgg({ StarterGem = 2, Pumpkin = 1 }, 0, 0), "Starter")
			t.eq(ShopRules.nextTrayEgg({ Starter = 1, SwampGem = 1 }, 0, 0), "Swamp")
		end,
		["the cheapest missing tier wins"] = function()
			t.eq(ShopRules.nextTrayEgg({ Swamp = 4 }, 0, 30_000), "Starter")
			t.eq(ShopRules.nextTrayEgg({ Starter = 1 }, 6, 0), "Swamp")
		end,
	}
end
