-- End-to-end checks of the real server services (tools/server-harness.luau): fake players join,
-- send intents and leave while the fake clock moves.
return function(t)
	local Valuation = t.require("src/shared/Valuation")
	local GameConfig = t.require("src/shared/Config/Game")

	local function count(map): number
		local n = 0
		for _ in map do
			n += 1
		end
		return n
	end

	local function mutant(id: number, tier: string, rarity: string, extra: { [string]: any }?)
		local item = {
			id = tostring(id),
			tier = tier,
			egg = tier,
			rarity = rarity,
			species = nil,
			mutations = {},
			size = 1,
			harvestedAt = 0,
		}
		for k, v in extra or {} do
			item[k] = v
		end
		return item
	end

	return {
		["a new player joins with starting Cash and eggs"] = function()
			local world = t.server()
			local _, data = world:join(1)
			t.eq(data.cash, 100)
			t.eq(data.eggs.Starter, 2)
		end,

		["pen income pays every minute online, carrying fractions"] = function()
			local world = t.server()
			-- One Swamp Legendary: 900 x 250 x 0.0005 = $112.50 a minute.
			local _, data = world:join(1, { inventory = { ["1"] = mutant(1, "Swamp", "Legendary") }, nextItemId = 2 })
			local before = data.cash
			world:advance(4 * 60 + 1, 0.25)
			t.eq(data.cash - before, 450) -- 112.5 x 4, the half dollars carried
		end,

		["offline pen income pays the offline rate for the whole time away, no cap"] = function()
			local world = t.server()
			local player, data =
				world:join(1, { inventory = { ["1"] = mutant(1, "Swamp", "Legendary") }, nextItemId = 2 })
			world:leave(player)
			local cash = data.cash
			world:advance(24 * 3600) -- a day away: 900 x 250 x 0.0001 x 1440 min = 32,400
			local _, back = world:join(1)
			t.eq(back.cash - cash, 32_400)
		end,

		["rebirth sells the bag at full value, counts it as earned, keeps pinned pen mutants"] = function()
			local world = t.server()
			local inventory = {}
			-- The pen: 8 pinned Starter Commons (low value, pinned so they stay).
			for i = 1, 8 do
				inventory[tostring(i)] = mutant(i, "Starter", "Common", { pinned = true })
			end
			-- 3 bagged mutants, each worth more than any pen mutant.
			inventory["9"] = mutant(9, "Swamp", "Rare")
			inventory["10"] = mutant(10, "Swamp", "Epic", { mutations = { "Golden" } })
			inventory["11"] = mutant(11, "Lab", "Common", { size = 1.4 })
			local player, data = world:join(1, {
				cash = 800_000,
				rebirths = 0,
				inventory = inventory,
				nextItemId = 12,
				stats = { totalCashEarned = 1_000_000 },
			})
			local expected = 0
			for _, id in { "9", "10", "11" } do
				expected += Valuation.sellValue(data.inventory[id], 1) -- cash multiplier 1 at rebirth 0
			end
			local earnedBefore = data.stats.totalCashEarned
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1)
			t.eq(data.stats.totalCashEarned - earnedBefore, expected, "totalCashEarned increase")
			t.eq(count(data.inventory), 8, "pen kept")
			for i = 1, 8 do
				t.ok(data.inventory[tostring(i)], "pinned mutant " .. i .. " kept")
			end
			t.eq(data.cash, GameConfig.startingCash)
		end,

		["pinning a low-value mutant keeps it in the pen over higher-value ones"] = function()
			local world = t.server()
			local inventory = { ["1"] = mutant(1, "Starter", "Common") }
			for i = 2, 10 do
				inventory[tostring(i)] = mutant(i, "Swamp", "Rare")
			end
			local player, data = world:join(1, { inventory = inventory, nextItemId = 11 })
			local DataService = world.service.DataService
			local function inPen(id)
				for _, item in DataService.penItems(data) do
					if item.id == id then
						return true
					end
				end
				return false
			end
			t.ok(not inPen("1"), "auto-fill leaves the Starter Common out")
			world:send(player, "Pin", "1", true)
			t.ok(data.inventory["1"].pinned, "pinned")
			t.ok(inPen("1"), "pinned mutant stands in the pen")
			t.eq(#DataService.penItems(data), GameConfig.penDisplayCount)
			-- Sell All skips it; unpinning returns it to the bag (and out of the pen).
			world:send(player, "SellAll")
			t.eq(count(data.inventory), 1)
			t.ok(data.inventory["1"], "pinned mutant not sold")
			world:send(player, "Pin", "1", false)
			t.eq(data.inventory["1"].pinned, nil)
		end,

		["pins are capped at the pen's size"] = function()
			local world = t.server()
			local inventory = {}
			for i = 1, 10 do
				inventory[tostring(i)] = mutant(i, "Starter", "Common")
			end
			local player, data = world:join(1, { inventory = inventory, nextItemId = 11 })
			for i = 1, 10 do
				world:send(player, "Pin", tostring(i), true)
			end
			local pinned = 0
			for _, item in data.inventory do
				if item.pinned then
					pinned += 1
				end
			end
			t.eq(pinned, GameConfig.penDisplayCount)
		end,

		["Auto-Harvest offline: 3 h of 5-minute eggs fills the bag and spends Cash"] = function()
			local world = t.server()
			local player, data = world:join(1, {
				cash = 1_000_000,
				slotCount = 10,
				eggs = { Swamp = 10 },
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
			})
			for i = 1, 10 do
				world:send(player, "Plant", i, "Swamp")
			end
			t.eq(count(data.slots), 10)
			t.eq(data.eggs.Swamp, nil, "all eggs planted")
			world:leave(player)
			local cash = data.cash
			world:advance(3 * 3600)
			local back, after = world:join(1)
			t.eq(count(after.inventory), GameConfig.inventoryCap, "bag full")
			t.ok(after.cash < cash, "Cash spent on replanting")
			-- Every egg past the first 10 was bought: 190 harvested, minus the 10 owned eggs,
			-- plus whatever is still growing (bought, planted, not yet harvested).
			local growing = count(after.slots)
			t.eq(cash - after.cash, (GameConfig.inventoryCap - 10 + growing) * 500, "Swamp eggs bought")
			local welcome = world:received(back, "WelcomeBack")
			t.eq(#welcome, 1)
			t.eq(welcome[1][1].autoHarvested, GameConfig.inventoryCap)
		end,

		["Auto-Harvest offline: rolls stop 2 h after leaving without Offline Mutations"] = function()
			local world = t.server({ seed = 7 })
			local player, data = world:join(1, {
				cash = 100_000_000,
				eggs = { Swamp = 2 },
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true, Luck2x = true },
				upgrades = { growthSpeed = 0, mutationOdds = 5 },
			})
			for i = 1, 2 do
				world:send(player, "Plant", i, "Swamp")
			end
			world:leave(player)
			world:advance(5 * 3600)
			world:join(1)
			-- Harvested more than the longest Swamp grow (15 min) after the cap: planted after it,
			-- so no rolls at all. Before the cap, mutations happen (max luck and odds).
			local capAt = data.lastSeen + GameConfig.offlineMutationCap
			local late, lateMutated, earlyMutated = 0, 0, 0
			for _, item in data.inventory do
				if item.harvestedAt <= capAt and #item.mutations > 0 then
					earlyMutated += 1
				end
				if item.harvestedAt > capAt + 15 * 60 then
					late += 1
					if #item.mutations > 0 then
						lateMutated += 1
					end
				end
			end
			t.ok(late > 0, "some harvests after the cap")
			t.eq(lateMutated, 0, "no mutations on eggs grown entirely after the cap")
			t.ok(earlyMutated > 0, "mutations before the cap")
		end,
	}
end
