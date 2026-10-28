-- Design revision: Lab unlocks on lifetime earnings at Rebirth 0, the tier gates shift down one,
-- Gem egg variants have their own doubled odds table, and the policy gate refuses Gem eggs.
return function(t)
	local Eggs = t.require("src/shared/Config/Eggs")
	local Rarities = t.require("src/shared/Config/Rarities")
	local ShopRules = t.require("src/shared/ShopRules")

	local function buyer(over)
		local b = { rebirths = 0, totalCashEarned = 0, cash = 1e12, gems = 1e9, paidRandomRestricted = false }
		for k, v in over or {} do
			b[k] = v
		end
		return b
	end

	return {
		["Rebirth Now is offered from 50% of the cost to just under it"] = function()
			t.eq(ShopRules.rebirthNowOffered(349_999, 700_000), false)
			t.eq(ShopRules.rebirthNowOffered(350_000, 700_000), true)
			t.eq(ShopRules.rebirthNowOffered(699_999, 700_000), true)
			t.eq(ShopRules.rebirthNowOffered(700_000, 700_000), false, "can rebirth with Cash")
		end,
		["the Rebirth Altar names what each rebirth unlocks"] = function()
			t.eq(ShopRules.unlockedAtRebirth(1), "Toxic")
			t.eq(ShopRules.unlockedAtRebirth(2), nil)
			t.eq(ShopRules.unlockedAtRebirth(3), "Void")
			t.eq(ShopRules.unlockedAtRebirth(6), "Cosmic")
			t.eq(ShopRules.unlockedAtRebirth(0), "Starter")
		end,
		["Lab unlocks when lifetime earnings cross 25,000, whatever the balance"] = function()
			t.ok(not ShopRules.isUnlocked("Lab", 0, 24_999), "locked at 24,999 earned")
			t.ok(ShopRules.isUnlocked("Lab", 0, 25_000), "unlocked at 25,000 earned")
			-- Spending doesn't matter: a player with $0 who earned 25K can buy Lab (funds aside).
			local ok, reason = ShopRules.canBuy("Lab", 1, buyer({ totalCashEarned = 25_000, cash = 0 }))
			t.ok(not ok and reason == "funds", "unlocked, just can't afford it")
			ok, reason = ShopRules.canBuy("Lab", 1, buyer({ totalCashEarned = 10_000, cash = 1e9 }))
			t.ok(not ok and reason == "locked", "rich but not enough earned: still locked")
			t.eq(ShopRules.nextLocked(0, 0), "Lab")
			t.eq(ShopRules.nextLocked(0, 25_000), "Toxic")
		end,
		["rebirth gates: Starter/Swamp/Lab 0, Toxic 1, Void 3, Cosmic 6"] = function()
			local expected = { Starter = 0, Swamp = 0, Lab = 0, Toxic = 1, Void = 3, Cosmic = 6 }
			for id, r in expected do
				t.eq(Eggs.tiers[id].unlockRebirth, r)
				t.ok(ShopRules.isUnlocked(id, r, 1e15), id .. " unlocked at its rebirth")
				if r > 0 then
					t.ok(not ShopRules.isUnlocked(id, r - 1, 1e15), id .. " locked one rebirth earlier")
				end
			end
			t.ok(ShopRules.isUnlocked("Lab", 1, 0), "after a rebirth Lab never needs the earnings again")
		end,
		["Toxic+ prices, grow times and values unchanged by the move"] = function()
			t.eq(Eggs.tiers.Toxic.cost, 50_000)
			t.eq(Eggs.tiers.Lab.growTime, 20 * 60)
			t.eq(Eggs.tiers.Cosmic.baseValue, 20_000_000)
		end,
		["every Gem egg: odds sum to 100, Uncommon+ exactly 2x the base before renormalizing"] = function()
			local gemPrices = { Starter = 15, Swamp = 40, Lab = 120, Toxic = 300, Void = 800, Cosmic = 2_000 }
			for _, baseId in Eggs.order do
				local base, gem = Eggs.tiers[baseId], Eggs.tiers[baseId .. "Gem"]
				t.ok(gem ~= nil, baseId .. " has a Gem variant")
				t.eq(gem.gemCost, gemPrices[baseId])
				t.eq(gem.growTime, base.growTime)
				t.eq(gem.baseValue, base.baseValue)
				t.eq(gem.unlockRebirth, base.unlockRebirth)
				t.eq(gem.unlockEarned, base.unlockEarned)
				t.eq(Eggs.baseOf(gem.id), baseId)
				local sum = 0
				for _, rarity in Rarities.order do
					sum += gem.odds[rarity]
				end
				t.near(sum, 100, 1e-9)
				-- Undo the renormalization with Common's scale (Common is not doubled).
				local scale = base.odds.Common / gem.odds.Common
				for _, rarity in Rarities.order do
					if rarity ~= "Common" then
						t.near(gem.odds[rarity] * scale, base.odds[rarity] * 2, 1e-9)
					end
				end
			end
		end,
		["Gem eggs cost Gems, x5 is 5x"] = function()
			local currency, amount = ShopRules.price("ToxicGem", 5)
			t.eq(currency, "Gems")
			t.eq(amount, 1_500)
			currency, amount = ShopRules.price("Toxic", 1)
			t.eq(currency, "Cash")
			t.eq(amount, 50_000)
		end,
		["Gem egg purchase refused for a restricted (or unknown) policy player"] = function()
			local ok, reason = ShopRules.canBuy("StarterGem", 1, buyer({ paidRandomRestricted = true }))
			t.ok(not ok and reason == "restricted", "restricted player refused")
			ok = ShopRules.canBuy("StarterGem", 1, buyer())
			t.ok(ok, "allowed player can buy")
			-- Cash eggs are not paid random items: the restriction doesn't apply.
			ok = ShopRules.canBuy("Starter", 1, buyer({ paidRandomRestricted = true }))
			t.ok(ok, "restricted player can still buy Cash eggs")
		end,
		["Gem egg gating matches the base tier"] = function()
			local ok, reason = ShopRules.canBuy("ToxicGem", 1, buyer({ rebirths = 0, totalCashEarned = 1e9 }))
			t.ok(not ok and reason == "locked", "Toxic Gem needs Rebirth 1")
			ok, reason = ShopRules.canBuy("LabGem", 1, buyer({ totalCashEarned = 100 }))
			t.ok(not ok and reason == "locked", "Lab Gem needs $25K earned")
		end,
	}
end
