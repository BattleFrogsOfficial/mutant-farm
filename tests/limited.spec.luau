-- Limited eggs (Config/LimitedEggs.lua) and the Pumpkin Egg: sale window, odds, the shop rules,
-- and buying / hatching / rebirth through the real server services.
return function(t)
	local Eggs = t.require("src/shared/Config/Eggs")
	local LimitedEggs = t.require("src/shared/Config/LimitedEggs")
	local Rarities = t.require("src/shared/Config/Rarities")
	local Mutants = t.require("src/shared/Config/Mutants")
	local ShopRules = t.require("src/shared/ShopRules")
	local Format = t.require("src/shared/Format")

	local pumpkin = Eggs.tiers.Pumpkin
	local INSIDE = pumpkin.startsAt + 3 * 86400

	local function count(map): number
		local n = 0
		for _ in map do
			n += 1
		end
		return n
	end

	local function find(list, pred)
		for _, v in list do
			if pred(v) then
				return v
			end
		end
		return nil
	end

	return {
		["window: active at startsAt and endsAt, inactive a second outside"] = function()
			t.eq(ShopRules.activeLimited(pumpkin.startsAt - 1), {})
			t.eq(ShopRules.activeLimited(pumpkin.startsAt), { "Pumpkin" })
			t.eq(ShopRules.activeLimited(pumpkin.endsAt), { "Pumpkin" })
			t.eq(ShopRules.activeLimited(pumpkin.endsAt + 1), {})
		end,
		["window: Oct 29 00:00 EDT to Nov 5 23:59 EST (DST ends Nov 1)"] = function()
			-- 2026-10-29 04:00 UTC and 2026-11-06 04:59 UTC.
			t.eq(pumpkin.startsAt, 1_793_246_400)
			t.eq(pumpkin.endsAt, 1_793_941_140)
			t.eq((pumpkin.endsAt - pumpkin.startsAt) % 3600, 59 * 60, "one more hour than calendar days: the DST hour")
		end,
		["Pumpkin: 600 Gems (x5 3,000), 30 min, Lab values, no gate"] = function()
			t.eq(ShopRules.price("Pumpkin", 1), "Gems")
			t.eq(select(2, ShopRules.price("Pumpkin", 1)), 600)
			t.eq(select(2, ShopRules.price("Pumpkin", 5)), 3_000)
			t.eq(pumpkin.growTime, 30 * 60)
			t.eq(pumpkin.baseValue, Eggs.tiers.Lab.baseValue)
			t.eq(pumpkin.baseValue, 11_000)
			t.ok(ShopRules.isUnlocked("Pumpkin", 0, 0), "no rebirth or earned gate")
			t.eq(pumpkin.design.pattern, "jack")
			t.eq(Eggs.sizeTier("Pumpkin"), "Lab")
			t.ok(table.find(Eggs.limitedOrder, "Pumpkin") ~= nil)
			t.ok(table.find(Eggs.order, "Pumpkin") == nil, "not a base tier")
		end,
		["Pumpkin odds sum to 100 and are Lab's Uncommon+ x2, renormalized"] = function()
			local lab = Eggs.tiers.Lab.odds
			local sum, raw = 0, 0
			for _, rarity in Rarities.order do
				sum += pumpkin.odds[rarity]
				raw += if rarity == "Common" then lab[rarity] else lab[rarity] * 2
			end
			t.near(sum, 100, 1e-9)
			for _, rarity in Rarities.order do
				local want = (if rarity == "Common" then lab[rarity] else lab[rarity] * 2) / raw * 100
				t.near(pumpkin.odds[rarity], want, 1e-9, rarity)
			end
			-- 70 / 20 / 8 / 1.9 / 0.1 -> raw 130: Common 53.85%, Legendary 0.154%.
			t.near(pumpkin.odds.Common, 70 / 130 * 100, 1e-9)
		end,
		["10 Halloween species, 2 per rarity, in bucket Pumpkin"] = function()
			for _, rarity in Rarities.order do
				local bucket = Mutants.buckets.Pumpkin[rarity]
				t.eq(#bucket, 2, rarity)
				for _, id in bucket do
					t.eq(Mutants.species[id].tier, "Pumpkin")
				end
			end
		end,
		["config entries carry everything the system needs"] = function()
			for _, e in LimitedEggs do
				for _, field in { "id", "name", "tagline", "icon", "event", "color", "design" } do
					t.ok(e[field] ~= nil, e.id .. " " .. field)
				end
				t.ok(e.priceGems > 0 and e.growSeconds > 0 and e.startsAt < e.endsAt, e.id .. " numbers")
				t.ok(Eggs.tiers[e.valueTier] ~= nil, e.id .. " valueTier")
				t.ok(Mutants.buckets[e.id] ~= nil, e.id .. " species bucket")
			end
		end,
		["policy: restricted buyers never see it and can't buy it"] = function()
			t.eq(ShopRules.shownLimited(INSIDE, true), {})
			t.eq(ShopRules.shownLimited(INSIDE, false), { "Pumpkin" })
			local buyer = {
				rebirths = 0,
				totalCashEarned = 0,
				cash = 0,
				gems = 10_000,
				paidRandomRestricted = true,
				now = INSIDE,
			}
			t.eq(select(2, ShopRules.canBuy("Pumpkin", 1, buyer)), "restricted")
			buyer.paidRandomRestricted = false
			t.eq(ShopRules.canBuy("Pumpkin", 1, buyer), true)
			buyer.now = pumpkin.endsAt + 1
			t.eq(select(2, ShopRules.canBuy("Pumpkin", 1, buyer)), "ended")
		end,
		["the ribbon's countdown text"] = function()
			t.eq(Format.timeLeft(3 * 86400 + 4 * 3600 + 59), "3d 4h")
			t.eq(Format.timeLeft(4 * 3600 + 12 * 60), "4h 12m")
			t.eq(Format.timeLeft(12 * 60 + 5), "12m")
			t.eq(Format.timeLeft(-5), "0m")
		end,

		["server: buy in the window (Gems sink LimitedEgg_Pumpkin), refused after it"] = function()
			local world = t.server({ now = INSIDE })
			local player, data = world:join(1, { gems = 5_000 })
			world:send(player, "BuyEgg", "Pumpkin", 5)
			t.eq(data.eggs.Pumpkin, 5)
			t.eq(data.gems, 2_000)
			t.ok(
				find(world.economy, function(e)
					return e.sku == "LimitedEgg_Pumpkin" and e.flow == "Sink" and e.amount == 3_000
				end),
				"Gems sink logged as LimitedEgg_Pumpkin"
			)
			t.ok(
				find(world.funnels, function(f)
					return f.step == "FirstLimitedEgg"
				end),
				"funnel step FirstLimitedEgg"
			)
			world.now = pumpkin.endsAt + 1
			world:send(player, "BuyEgg", "Pumpkin", 1)
			t.eq(data.eggs.Pumpkin, 5, "not on sale after endsAt")
			t.eq(data.gems, 2_000)
		end,
		["server: restricted player is refused"] = function()
			local world = t.server({ now = INSIDE })
			world.restricted[1] = true
			local player, data = world:join(1, { gems = 5_000 })
			world:send(player, "BuyEgg", "Pumpkin", 1)
			t.eq(data.eggs.Pumpkin, nil)
			t.eq(data.gems, 5_000)
		end,
		["server: after the window owned eggs still plant and hatch into Pumpkin species at Lab value"] = function()
			local world = t.server({ now = pumpkin.endsAt + 86400 })
			local player, data = world:join(1, { eggs = { Pumpkin = 1 }, grantedStarterEggs = true })
			world:send(player, "Plant", 1, "Pumpkin")
			t.eq(data.slots["1"].eggId, "Pumpkin")
			world:advance(3 * 30 * 60 + 5) -- longest (Legendary) grow
			world:send(player, "Harvest", 1)
			local item = data.inventory["1"]
			t.ok(item, "hatched")
			t.eq(item.tier, "Pumpkin")
			t.eq(item.egg, "Pumpkin")
			t.eq(Mutants.species[item.species].tier, "Pumpkin")
			t.ok(data.almanac[item.species] ~= nil, "counts in the Almanac")
		end,
		["server: rebirth keeps owned and planted Pumpkin eggs (back to the bag)"] = function()
			local world = t.server({ now = INSIDE })
			local player, data = world:join(1, {
				cash = 800_000,
				eggs = { Pumpkin = 2 },
				grantedStarterEggs = true,
			})
			world:send(player, "Plant", 1, "Pumpkin")
			t.eq(data.eggs.Pumpkin, 1)
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1)
			t.eq(data.eggs.Pumpkin, 2)
			t.eq(count(data.slots), 0)
		end,
		["server: SeenLimited remembers the first shop open, once per egg"] = function()
			local world = t.server({ now = INSIDE })
			local player, data = world:join(1)
			t.eq(data.seenLimited.Pumpkin, nil)
			world:send(player, "SeenLimited", "Pumpkin")
			t.eq(data.seenLimited.Pumpkin, true)
			world:send(player, "SeenLimited", "Starter") -- not a limited egg: ignored
			t.eq(data.seenLimited.Starter, nil)
		end,
	}
end
