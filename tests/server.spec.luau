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

		["leaderboards: 3 players populate Top Pens and Top Rebirths, top first"] = function()
			local world = t.server()
			local Leaderboards = t.require("src/shared/Leaderboards")
			local players = {}
			for i, setup in { { 2, "Swamp" }, { 5, "Lab" }, { 0, "Starter" } } do
				players[i] = world:join(i, {
					rebirths = setup[1],
					inventory = { ["1"] = mutant(1, setup[2], "Rare") },
					nextItemId = 2,
				})
			end
			world:advance(GameConfig.leaderboardSeconds + 1, 1)
			t.eq(world.ordered.TopPens_v1["2"], 110_000) -- Lab 11K x Rare 10
			t.eq(world.ordered.TopRebirths_v1["2"], 5)
			-- The last broadcast has both boards, best first, and leaderstats are filled.
			local last
			for _, m in world.broadcast do
				if m.name == "Leaderboards" then
					last = m.args[1]
				end
			end
			t.ok(last, "boards sent to clients")
			t.eq(#last.pens, 3)
			t.eq(#last.rebirths, 3)
			t.eq(last.pens[1].userId, 2)
			t.eq(last.rebirths[1].value, 5)
			t.eq(last.rebirths[3].userId, 3)
			t.eq(Leaderboards.rankOf(last.pens, 1), 2)
			t.eq(Leaderboards.rankOf(last.pens, 99), nil)
			t.eq(players[2]:FindFirstChild("leaderstats"):FindFirstChild("Rebirths").Value, 5)
		end,

		["VIP daily Gems: claim once per UTC day"] = function()
			local world = t.server({ now = 1_800_000_000 - 1_800_000_000 % 86400 + 3600 })
			local player, data = world:join(1, { ownedPasses = { VIP = true } })
			t.eq(player:GetAttribute("VIP"), true, "chat tag attribute")
			world:send(player, "ClaimVipGems")
			t.eq(data.gems, 50)
			world:send(player, "ClaimVipGems")
			t.eq(data.gems, 50, "second claim the same day")
			world:advance(86400)
			world:send(player, "ClaimVipGems")
			t.eq(data.gems, 100, "next day")
			-- Not VIP: nothing.
			local other, otherData = world:join(2)
			world:send(other, "ClaimVipGems")
			t.eq(otherData.gems, 0)
			t.eq(other:GetAttribute("VIP"), false)
		end,

		["buying VIP: sparkle for everyone, a chat line, the tag"] = function()
			local world = t.server()
			world.modules("src/shared/Config/Passes").VIP.id = 4242
			local player, data = world:join(7)
			world.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 4242, true)
			world:runDue()
			t.ok(data.ownedPasses.VIP)
			t.eq(player:GetAttribute("VIP"), true)
			local fx
			for _, m in world.broadcast do
				if m.name == "PurchaseFx" then
					fx = m.args
				end
			end
			t.ok(fx, "PurchaseFx sent to all")
			t.eq(fx[1], 7)
			t.eq(fx[2], "Player7 just went VIP!")
			world.modules("src/shared/Config/Passes").VIP.id = 0
		end,

		["group: offered once at the first sell; joining mid-session pays on the next sell"] = function()
			local world = t.server({ groupId = 777 })
			local inventory = {}
			for i = 1, 3 do
				inventory[tostring(i)] = mutant(i, "Swamp", "Common")
			end
			local player, data = world:join(1, { inventory = inventory, nextItemId = 4 })
			t.eq(data.inGroup, false)
			world:send(player, "Sell", "1")
			t.eq(#world:received(player, "GroupOffer"), 1, "offered at the first sell")
			world:advance(60)
			world:send(player, "Sell", "2")
			t.eq(#world:received(player, "GroupOffer"), 1, "only once")
			-- Joins the group mid-session (not via the offer): the next sell re-checks and pays +10%.
			world.groups[1] = { 777 }
			world:advance(60)
			local cash = data.cash
			world:send(player, "Sell", "3")
			t.eq(data.inGroup, true)
			t.eq(data.cash - cash, math.floor(900 * 1.1))
			-- Claim gives the eggs once.
			world:send(player, "ClaimGroupReward")
			t.eq(data.eggs.Swamp, 2)
			t.eq(data.groupRewardClaimed, true)
			-- A member is checked with IsInGroup on join.
			world:leave(player)
			world.groups[1] = {}
			local _, back = world:join(1)
			t.eq(back.inGroup, false, "left the group: bonus off at next join")
		end,

		["Studio warns about every pass/product whose id is still 0"] = function()
			local world = t.server()
			local found
			for _, w in world.warnings do
				if w:find("not linked", 1, true) then
					found = w
				end
			end
			t.ok(found, "warning printed")
			for _, name in { "pass VIP", "pass Luck2x", "product Gems100", "product StarterBundle" } do
				t.ok(found:find(name, 1, true), name .. " listed")
			end
		end,

		["Rebirth Now: sells the bag first, rebirths, then takes 100 Gems"] = function()
			local world = t.server()
			local inventory = {}
			for i = 1, 8 do
				inventory[tostring(i)] = mutant(i, "Starter", "Common", { pinned = true })
			end
			inventory["9"] = mutant(9, "Swamp", "Epic")
			local player, data = world:join(1, {
				cash = 400_000, -- 57% of the 700K first rebirth
				gems = 150,
				inventory = inventory,
				nextItemId = 10,
			})
			local earned = data.stats.totalCashEarned
			local value = Valuation.sellValue(data.inventory["9"], 1)
			world:send(player, "RebirthNow")
			t.eq(data.rebirths, 1)
			t.eq(data.gems, 50)
			t.eq(data.cash, GameConfig.startingCash)
			t.eq(data.stats.totalCashEarned - earned, value, "bag sold first and counted as earned")
			t.eq(count(data.inventory), 8, "pen kept")
			-- Logged: the sale (Source) before the Gems sink, which is logged as RebirthNow.
			local saleAt, gemsAt
			for i, e in world.economy do
				if e.sku == "Sell_Swamp_Epic" then
					saleAt = i
				elseif e.sku == "RebirthNow" then
					gemsAt = i
					t.eq(e.amount, 100)
				end
			end
			t.ok(saleAt and gemsAt and saleAt < gemsAt, "sale logged before the Gems")
		end,

		["Rebirth Now: not below 50% of the cost, not without the Gems, works when restricted"] = function()
			local world = t.server()
			local poor, poorData = world:join(1, { cash = 340_000, gems = 500 }) -- 48.6%
			world:send(poor, "RebirthNow")
			t.eq(poorData.rebirths, 0)
			t.eq(poorData.gems, 500)
			local broke, brokeData = world:join(2, { cash = 600_000, gems = 99 })
			world:send(broke, "RebirthNow")
			t.eq(brokeData.rebirths, 0)
			t.eq(brokeData.cash, 600_000, "nothing reset")
			world.restricted[3] = true -- no randomness: not policy-gated
			local restricted, data = world:join(3, { cash = 350_000, gems = 100 })
			world:send(restricted, "RebirthNow")
			t.eq(data.rebirths, 1)
			t.eq(data.gems, 0)
		end,

		["Gem upgrades: Gems spent, Pen Slots once per rebirth level, all kept through rebirth"] = function()
			local world = t.server()
			local player, data = world:join(1, { gems = 5_000, cash = 800_000 })
			local DataService = world.service.DataService
			local cap = DataService.penCapacity(data)
			world:send(player, "BuyGemUpgrade", "penSlots")
			t.eq(data.gemUpgrades.penSlots, 1)
			t.eq(DataService.penCapacity(data), cap + 4)
			t.eq(data.gems, 5_000 - 150)
			world:send(player, "BuyGemUpgrade", "penSlots") -- already bought at Rebirth 0
			t.eq(data.gemUpgrades.penSlots, 1)
			local luck = DataService.luck(data)
			world:send(player, "BuyGemUpgrade", "luck")
			t.near(DataService.luck(data), luck * 1.1, 1e-9, "+10% luck")
			world:send(player, "BuyGemUpgrade", "offline")
			world:send(player, "BuyGemUpgrade", "bogus")
			t.eq(data.gems, 5_000 - 150 - 200 - 100)
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1)
			t.eq(data.gemUpgrades.penSlots, 1, "kept through rebirth")
			t.eq(data.gemUpgrades.luck, 1)
			t.eq(data.gemUpgrades.offline, 1)
			world:send(player, "BuyGemUpgrade", "penSlots") -- a new rebirth level: again
			t.eq(data.gemUpgrades.penSlots, 2)
			-- Not enough Gems: nothing happens.
			local poor, poorData = world:join(2, { gems = 10 })
			world:send(poor, "BuyGemUpgrade", "luck")
			t.eq(poorData.gemUpgrades.luck, 0)
			t.eq(poorData.gems, 10)
		end,

		["$/min: growing eggs count before the first harvest, in the snapshot and on the gate"] = function()
			local world = t.server()
			local player, data = world:join(1, { eggs = { Starter = 2 }, grantedStarterEggs = true })
			local DataService = world.service.DataService
			t.eq(DataService.incomePerMinute(data), 0, "nothing growing, empty pen")
			world:send(player, "Plant", 1, "Starter")
			world:send(player, "Plant", 2, "Starter")
			world:advance(60)
			local income = DataService.incomePerMinute(data)
			t.ok(income > 0, "2 Starters growing: income > 0")
			-- Roughly two Starter eggs' expected value per grow time (Starter ~1 min): tens of $/min.
			t.ok(income >= 2 * 50 and income < 2 * 2000, "plausible: " .. income)
			local states = world:received(player, "State")
			local last = states[#states] and states[#states][1]
			t.ok(last and last.incomePerMinute > 0, "the snapshot carries it")
			-- Watering doubles the growing part.
			world:send(player, "Water")
			t.ok(DataService.incomePerMinute(data) > income * 1.5, "watered: about 2x")
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
