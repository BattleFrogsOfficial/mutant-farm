-- End-to-end checks of the real server services (tools/server-harness.luau): fake players join,
-- send intents and leave while the fake clock moves.
return function(t)
	local Valuation = t.require("src/shared/Valuation")
	local GameConfig = t.require("src/shared/Config/Game")
	local Growth = t.require("src/shared/Growth")

	local function DataService(world)
		return world.service.DataService
	end

	local function count(map): number
		local n = 0
		for _ in map do
			n += 1
		end
		return n
	end

	-- A fully grown egg on a patch.
	local function grown(eggId: string, rarity: string)
		local required = Growth.requiredSeconds(eggId, rarity)
		return {
			eggId = eggId,
			rarity = rarity,
			mutations = {},
			size = 1,
			plantedAt = 0,
			growth = required,
			updatedAt = 1_800_000_000,
			rollsDone = 10,
			lastRollAt = 1_800_000_000,
		}
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
		["a new player joins with starting Cash, one egg in the bag and one ready in 10 s"] = function()
			local world = t.server()
			local _, data = world:join(1)
			t.eq(data.cash, 100)
			t.eq(data.eggs.Starter, 1)
			t.eq(data.onboarding.active, true)
			t.eq(data.bundleOfferEndsAt, 0, "no Starter Bundle window on join")
			local slot = data.slots["1"]
			t.ok(slot ~= nil and slot.eggId == "Starter" and slot.scripted == "firstHatch", "pre-planted on patch 1")
			local Growth = world:modulesRequire("src/shared/Growth")
			t.near(Growth.slotRequired(slot) - slot.growth, 10, 1e-6, "10 s from hatching")
			t.eq(data.stats.eggsPlanted, 1, "counts as the first egg, so the next plant is the Rare")
		end,

		["the scripted first hatch: Starter Common, Glitched, 0.8, sells for ~$115, exactly once"] = function()
			local world = t.server()
			local player, data = world:join(1)
			local seen = {}
			local Analytics = world:modulesRequire("src/server/Util/Analytics")
			Analytics.observer = function(_, name)
				table.insert(seen, name)
			end
			local funnel = {}
			Analytics.funnelObserver = function(_, step, seconds)
				funnel[step] = seconds or -1
			end
			world:advance(11, 1)
			world:send(player, "Harvest", 1)
			local item
			for _, it in data.inventory do
				item = it
			end
			t.ok(item ~= nil, "hatched")
			t.eq(item.rarity, "Common")
			t.eq(table.concat(item.mutations, ","), "Glitched")
			t.eq(item.size, 0.8)
			t.eq(item.valueScale, 0.2)
			t.eq(item.scripted, "firstHatch")
			t.eq(data.almanac[item.species].firstHatch, true, "the Almanac entry wears the ribbon")
			t.eq(#seen, 0, "no hatch / mutation analytics for a scripted outcome")
			-- Top Pens never counts it.
			local Leaderboards = world:modulesRequire("src/shared/Leaderboards")
			t.eq(Leaderboards.penValue({ item }), 0)
			local before = data.cash
			world:send(player, "Sell", item.id)
			local got = data.cash - before
			t.ok(got >= 100 and got <= 130, "sold for " .. got)
			local notes = world:received(player, "Notify")
			t.eq(notes[#notes][1], "$115! Buy more eggs and grow your farm.", "the first sale's toast")
			-- The funnel's FirstHatch and FirstSell carry seconds since join.
			t.near(funnel.FirstHatch, 11, 1.01, "FirstHatch at ~11 s")
			t.near(funnel.FirstSell, 11, 1.01, "FirstSell at ~11 s")
			-- The next hatch is a normal one (the guaranteed Rare: the 2nd egg planted).
			world:send(player, "Plant", 1, "Starter")
			world:advance(3600, 5)
			world:send(player, "Harvest", 1)
			local second
			for _, it in data.inventory do
				second = it
			end
			t.ok(second ~= nil and second.scripted == nil and second.valueScale == nil, "a real hatch")
			t.eq(second.rarity, "Rare")
			t.ok(table.find(seen, "Hatch_Rare") ~= nil, "real hatches are logged")
			-- The Starter Bundle window starts on this reveal (not on join), and the reveal offers it.
			local harvests = world:received(player, "Harvested")
			t.eq(harvests[#harvests][7], "StarterBundle", "offered on the Rare's reveal")
			t.eq(harvests[1][7], nil, "not on the scripted first hatch")
			t.ok(data.bundleOfferEndsAt > world.now + 500, "the 10-minute window runs from the reveal")
			t.eq(data.onboarding.bundle, true)
		end,

		["the grow ramp: Starter only, 10 / 20 / 30 s by hatches so far, gone from hatch 30"] = function()
			local world = t.server()
			local player, data = world:join(1)
			local Growth = world:modulesRequire("src/shared/Growth")
			data.slots = {}
			data.eggs = { Starter = 10, Swamp = 2 }
			local function plantAt(hatches, eggId)
				data.stats.hatchesThisLife = hatches
				data.stats.eggsPlanted = 5 -- past the guaranteed Rare
				world:send(player, "Plant", 1, eggId)
				local slot = data.slots["1"]
				data.slots["1"] = nil
				return slot.baseGrow, Growth.slotRequired(slot), slot.rarity
			end
			t.eq((plantAt(1, "Starter")), 10)
			t.eq((plantAt(9, "Starter")), 10)
			t.eq((plantAt(10, "Starter")), 20)
			t.eq((plantAt(29, "Starter")), 30)
			local base, required, rarity = plantAt(30, "Starter")
			t.eq(base, nil, "no ramp from hatch 30")
			t.eq(required, Growth.requiredSeconds("Starter", rarity))
			t.eq((plantAt(1, "Swamp")), nil, "Starter only")
			-- Every profile ramps (2026-11-04), returning ones too, by hatches this life.
			local p2, d2 = world:join(2, { grantedStarterEggs = true, eggs = { Starter = 1 } })
			d2.stats.eggsPlanted = 5
			world:send(p2, "Plant", 1, "Starter")
			t.eq(d2.slots["1"].baseGrow, 10)
		end,

		["the grow ramp restarts each life"] = function()
			local world = t.server()
			local player, data = world:join(1, {
				grantedStarterEggs = true,
				cash = 800_000,
				eggs = { Starter = 2 },
				stats = { cashEarnedThisLife = 800_000, hatchesThisLife = 40, harvested = 40, eggsPlanted = 40 },
			})
			world:send(player, "Plant", 1, "Starter")
			t.eq(data.slots["1"].baseGrow, nil, "past the ramp this life")
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1)
			t.eq(data.stats.hatchesThisLife, 0)
			t.eq(data.stats.harvested, 40, "lifetime count kept")
			world:send(player, "Plant", 1, "Starter")
			t.eq(data.slots["1"].baseGrow, 10, "fast again in the new life")
		end,

		["rebirth needs Cash EARNED this life: banked mutants can't chain rebirths"] = function()
			local world = t.server()
			local inventory = {}
			for i = 1, 8 do
				inventory[tostring(i)] = mutant(i, "Starter", "Common", { pinned = true })
			end
			-- $5.5M in two bagged Lab Legendaries (2.75M each), nothing earned yet this life.
			inventory["9"] = mutant(9, "Lab", "Legendary")
			inventory["10"] = mutant(10, "Lab", "Legendary")
			local player, data = world:join(1, {
				grantedStarterEggs = true,
				inventory = inventory,
				nextItemId = 11,
				stats = { cashEarnedThisLife = 0 },
			})
			t.eq(Valuation.sellValue(data.inventory["9"], 1), 2_750_000)
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 0, "$0 earned this life: refused")
			world:send(player, "RebirthNow")
			t.eq(data.rebirths, 0, "Rebirth Now too")
			-- Selling one earns 2.75M: exactly one rebirth (700K).
			world:send(player, "Sell", "9")
			t.eq(data.stats.cashEarnedThisLife, 2_750_000)
			local lifetime = data.stats.totalCashEarned
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1)
			-- The rebirth sold the other Legendary: counted for the lifetime total, never this life.
			t.eq(data.inventory["10"], nil, "bag sold")
			t.eq(data.stats.totalCashEarned - lifetime, 2_750_000)
			t.eq(data.stats.cashEarnedThisLife, 0)
			world:send(player, "Rebirth")
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1, "no chain of rebirths from banked value")
			-- Cash held doesn't count either.
			data.cash = 50_000_000
			world:send(player, "Rebirth")
			t.eq(data.rebirths, 1)
		end,

		["the Starter Bundle waits for the first Rare across a rejoin"] = function()
			local world = t.server()
			local player = world:join(1)
			world:leave(player)
			world:advance(60)
			local _, back = world:join(1)
			t.eq(back.bundleOfferEndsAt, 0, "still waiting for the Rare's reveal")
			t.eq(back.onboarding.active, true)
			t.eq(back.eggs.Starter, 1, "starting eggs granted once")
		end,

		["a returning profile gets none of the opening"] = function()
			local world = t.server()
			local player, data = world:join(1, { grantedStarterEggs = true, eggs = { Starter = 2 } })
			t.eq(data.onboarding.active, false)
			t.eq(next(data.slots), nil, "nothing pre-planted")
			t.eq(data.eggs.Starter, 2)
			world:send(player, "OpenedShop")
			t.eq(data.onboarding.shopOpened, false, "nothing to retire")
		end,

		["solo weather: one free Solar Flare after 2:30 with 3 eggs growing, no global event near"] = function()
			-- A start time well clear of any global event for the next ~10 minutes.
			local Weather = t.require("src/shared/Weather")
			local start = 1_800_000_000
			while true do
				local e = Weather.scheduleAt(start)
				if not e.active and e.startsAt - start > 900 then
					break
				end
				start += 60
			end
			local world = t.server({ now = start })
			local player, data = world:join(1)
			data.slots = {}
			data.eggs = { Swamp = 6 }
			-- 2:30 of play with nothing growing: no weather yet.
			world:advance(151, 1)
			t.eq(data.onboarding.weather, false, "needs 3 eggs growing")
			for i = 1, 2 do
				world:send(player, "Plant", i, "Swamp")
			end
			world:advance(3, 1)
			t.eq(data.onboarding.weather, false, "2 growing isn't enough")
			world:send(player, "Plant", 3, "Swamp")
			world:advance(2, 1)
			t.eq(data.onboarding.weather, true, "fired")
			t.eq(player:GetAttribute("PlotWeatherId"), "SolarFlare", "on the player's plot")
			local toasts = {}
			for _, n in world:received(player, "Notify") do
				table.insert(toasts, n[1])
			end
			t.eq(#toasts, 0, "no toast: the tutorial card says WEATHER! (the toast lane is for events)")
			-- Never again: once it ended, more growing eggs don't bring another.
			world:advance(200, 1)
			t.eq(player:GetAttribute("PlotWeatherId"), nil, "the event ended")
			world:send(player, "Plant", 4, "Swamp")
			world:advance(10, 1)
			t.eq(player:GetAttribute("PlotWeatherId"), nil, "once per profile")
			-- A returning profile never gets it.
			local p2, d2 = world:join(2, { grantedStarterEggs = true, eggs = { Swamp = 3 } })
			for i = 1, 3 do
				world:send(p2, "Plant", i, "Swamp")
			end
			world:advance(200, 1)
			t.eq(d2.onboarding.weather, false)
			t.eq(p2:GetAttribute("PlotWeatherId"), nil)
		end,

		["solo weather waits while a global event is near"] = function()
			local Weather = t.require("src/shared/Weather")
			-- 2:30 of play ends ~2 min before a global event starts.
			local start = 1_800_000_000
			while true do
				local e = Weather.scheduleAt(start)
				if not e.active and e.startsAt - start > 260 and e.startsAt - start < 300 then
					break
				end
				start += 5
			end
			local world = t.server({ now = start })
			local player, data = world:join(1)
			data.slots = {}
			data.eggs = { Swamp = 3 }
			for i = 1, 3 do
				world:send(player, "Plant", i, "Swamp")
			end
			world:advance(160, 1)
			t.eq(data.onboarding.weather, false, "a global event starts within 5 min")
		end,

		["opening the Egg Shop once retires the tray's BUY button for good"] = function()
			local world = t.server()
			local player, data = world:join(1)
			t.eq(data.onboarding.shopOpened, false)
			world:send(player, "OpenedShop")
			t.eq(data.onboarding.shopOpened, true)
			world:advance(1) -- snapshots go out batched
			local snaps = world:received(player, "State")
			t.eq(snaps[#snaps][1].onboarding.shopOpened, true, "the HUD hears it")
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
				stats = { totalCashEarned = 1_000_000, cashEarnedThisLife = 800_000 },
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

		["Studio warns about every pass/product whose id is still 0 (and only those)"] = function()
			local function notLinked(world)
				for _, w in world.warnings do
					if w:find("not linked", 1, true) then
						return w
					end
				end
				return nil
			end
			-- Every id is linked in Config: no warning.
			t.eq(notLinked(t.server()), nil, "all ids linked")
			local found = notLinked(t.server({
				unlinked = { passes = { "VIP", "Luck2x" }, products = { "Gems100", "StarterBundle" } },
			}))
			t.ok(found, "warning printed")
			for _, name in { "pass VIP", "pass Luck2x", "product Gems100", "product StarterBundle" } do
				t.ok(found:find(name, 1, true), name .. " listed")
			end
			t.ok(not found:find("pass AutoHarvest", 1, true), "linked ones aren't listed")
		end,

		["Rebirth Now: sells the bag first, rebirths, then takes 100 Gems"] = function()
			local world = t.server()
			local inventory = {}
			for i = 1, 8 do
				inventory[tostring(i)] = mutant(i, "Starter", "Common", { pinned = true })
			end
			inventory["9"] = mutant(9, "Swamp", "Epic")
			local player, data = world:join(1, {
				cash = 400_000,
				stats = { cashEarnedThisLife = 400_000 }, -- 57% of the 700K first rebirth
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
			local poor, poorData =
				world:join(1, { cash = 340_000, gems = 500, stats = { cashEarnedThisLife = 340_000 } }) -- 48.6%
			world:send(poor, "RebirthNow")
			t.eq(poorData.rebirths, 0)
			t.eq(poorData.gems, 500)
			local broke, brokeData =
				world:join(2, { cash = 600_000, gems = 99, stats = { cashEarnedThisLife = 600_000 } })
			world:send(broke, "RebirthNow")
			t.eq(brokeData.rebirths, 0)
			t.eq(brokeData.cash, 600_000, "nothing reset")
			world.restricted[3] = true -- no randomness: not policy-gated
			local restricted, data =
				world:join(3, { cash = 350_000, gems = 100, stats = { cashEarnedThisLife = 350_000 } })
			world:send(restricted, "RebirthNow")
			t.eq(data.rebirths, 1)
			t.eq(data.gems, 0)
		end,

		["Gem upgrades: Gems spent, Pen Slots once per rebirth level, all kept through rebirth"] = function()
			local world = t.server()
			local player, data =
				world:join(1, { gems = 5_000, cash = 800_000, stats = { cashEarnedThisLife = 800_000 } })
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

		["watering: the pad grows 2x while you stand on it, a tap boosts at the server's offer for 5 s"] = function()
			local world = t.server()
			local player, data = world:join(1, { eggs = { Swamp = 1 }, grantedStarterEggs = true })
			local WaterService = world.service.WaterService
			local water = GameConfig.water
			t.ok(data.waterOffer >= 3 and data.waterOffer <= 10, "an offer is rolled on join")
			t.eq(data.onPad, false)
			world:send(player, "Plant", 1, "Swamp")
			local slot = data.slots["1"]

			-- On the pad for 10 s: 20 s of growth.
			WaterService.setOnPad(player, true)
			t.eq(data.onPad, true)
			world:advance(10)
			WaterService.setOnPad(player, false)
			t.near(slot.growth, 20, 1e-6)

			-- Off the pad a tap does nothing (the boost belongs to the pad).
			world:send(player, "TapBoost")
			t.eq(data.stats.waters, 0, "off the pad: refused")
			-- Tap on the pad: the offered multiplier for 5 s, then the pad's 2x, and a fresh offer.
			WaterService.setOnPad(player, true)
			local offer = data.waterOffer
			local tappedAt = world.now
			world:send(player, "TapBoost")
			t.eq(data.waterMult, offer)
			t.near(data.wateredUntil, tappedAt + water.tapSeconds, 1e-9)
			t.ok(data.waterOffer >= 3 and data.waterOffer <= 10, "a new offer")
			t.eq(data.stats.waters, 1)
			-- Tapping again on the cooldown does nothing.
			local next = data.waterOffer
			world:advance(1)
			world:send(player, "TapBoost")
			t.eq(data.stats.waters, 1, "ignored on the cooldown")
			t.eq(data.waterOffer, next)
			-- After the boost: 5 s at the offer, then back to the pad's 2x for 5 s.
			world:advance(9)
			world.service.GrowthService.settle(data, world.now)
			t.near(slot.growth, 20 + offer * water.tapSeconds + 2 * 5, 1e-6)
			world:send(player, "TapBoost")
			t.eq(data.stats.waters, 2, "a tap after the boost runs out counts")

			-- The pad and the boost don't multiply: the higher applies.
			local g0 = slot.growth
			world:advance(water.tapSeconds)
			world.service.GrowthService.settle(data, world.now)
			t.near(slot.growth - g0, data.waterMult * water.tapSeconds, 1e-6)
			WaterService.setOnPad(player, false)

			-- Leaving: nobody's on the pad and nothing is watered while away.
			world:leave(player)
			local saved = world.saved["1"]
			t.eq(saved.onPad, false)
			t.ok(saved.wateredUntil <= world.now, "the boost ends when you leave")
			local g1 = saved.slots["1"].growth
			world:advance(60)
			local _, back = world:join(1)
			t.near(back.slots["1"].growth - g1, 60, 1e-6, "dry while away")
			t.eq(back.onPad, false)
		end,

		["offline mutation rolls run at 25% of the online chance (catch-up on join)"] = function()
			local world = t.server()
			local player = world:join(1, { eggs = { Swamp = 3 }, grantedStarterEggs = true })
			for i = 1, 3 do
				world:send(player, "Plant", i, "Swamp")
			end
			world:advance(1)
			world:leave(player)
			-- Watch the chance scale every roll uses while the server catches up on rejoin.
			local Rolls = world:modulesRequire("src/shared/Rolls")
			local scales = {}
			local real = Rolls.rollMutations
			Rolls.rollMutations = function(rng, existing, luck, odds, scale)
				table.insert(scales, scale or 1)
				return real(rng, existing, luck, odds, scale)
			end
			world:advance(30 * 60) -- 30 min away: inside the 2 h cap
			world:join(1)
			Rolls.rollMutations = real
			t.ok(#scales > 0, "rolls happened offline")
			for _, s in scales do
				t.eq(s, GameConfig.offlineMutationChanceScale, "offline scale")
			end
			t.eq(GameConfig.offlineMutationChanceScale, 0.25)
		end,

		["$/min is the pen's income only: growing eggs earn nothing, a pen mutant does"] = function()
			local world = t.server()
			local player, data = world:join(1, { eggs = { Starter = 2 }, grantedStarterEggs = true })
			local DataService = world.service.DataService
			t.eq(DataService.incomePerMinute(data), 0, "nothing growing, empty pen")
			world:send(player, "Plant", 1, "Starter")
			world:send(player, "Plant", 2, "Starter")
			world:advance(30)
			t.eq(DataService.incomePerMinute(data), 0, "growing eggs give no $/min")
			world:send(player, "TapBoost")
			t.eq(DataService.incomePerMinute(data), 0, "a growth boost changes nothing")
			-- Ripe eggs: still $0, and a fresh snapshot says they're ready (the HATCH EGGS hint).
			local sent = #world:received(player, "State")
			world:advance(10 * 60, GameConfig.growthTickSeconds)
			local after = world:received(player, "State")
			t.ok(#after > sent, "a snapshot went out when they matured")
			local snap = after[#after][1]
			t.eq(snap.incomePerMinute, 0)
			t.eq(snap.growingCount, 0)
			t.eq(snap.readyCount, 2)
			-- Hatched: the mutants stand in the pen and earn its income (cents kept).
			world:send(player, "HarvestAll")
			local income = DataService.incomePerMinute(data)
			t.ok(income > 0, "pen mutants earn: " .. income)
			t.near(income, math.floor(DataService.penIncome(data) * 100) / 100, 1e-9)
			world:advance(1) -- snapshots go out batched
			local last = world:received(player, "State")
			t.eq(last[#last][1].incomePerMinute, income, "the snapshot carries it")
		end,

		["Auto-Harvest: a Common is sold at once, an Uncommon is kept"] = function()
			local world = t.server()
			local player, data = world:join(1, {
				cash = 0,
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				slots = { ["1"] = grown("Starter", "Common"), ["2"] = grown("Swamp", "Uncommon") },
			})
			local earned = data.stats.totalCashEarned
			world:advance(GameConfig.growthTickSeconds + 1)
			t.eq(count(data.inventory), 1, "only the Uncommon kept")
			local _, kept = next(data.inventory)
			t.eq(kept.rarity, "Uncommon")
			t.eq(data.stats.sold, 1, "the Common was sold")
			t.ok(data.stats.totalCashEarned > earned, "the sale counts as earned")
			local notes = world:received(player, "Notify")
			t.ok(#notes > 0 and string.find(notes[#notes][1], "Auto%-sold 1 Common") ~= nil, "one summary toast")
		end,

		["Auto-Harvest: pinned mutants in the bag are never sold"] = function()
			local world = t.server()
			local _, data = world:join(1, {
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				inventory = { ["1"] = mutant(1, "Starter", "Common", { pinned = true }) },
				nextItemId = 2,
				slots = { ["1"] = grown("Starter", "Common") },
			})
			world:advance(GameConfig.growthTickSeconds + 1)
			t.ok(data.inventory["1"] ~= nil and data.inventory["1"].pinned, "the pinned Common stays")
			t.eq(data.stats.sold, 1, "only the new Common was sold")
		end,

		["Auto-Harvest: with a full bag a Common still sells, an Uncommon waits on its patch"] = function()
			local world = t.server()
			local inventory = {}
			for i = 1, GameConfig.inventoryCap do
				inventory[tostring(i)] = mutant(i, "Starter", "Rare")
			end
			local _, data = world:join(1, {
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				inventory = inventory,
				nextItemId = GameConfig.inventoryCap + 1,
				slots = { ["1"] = grown("Starter", "Common"), ["2"] = grown("Swamp", "Uncommon") },
			})
			world:advance(GameConfig.growthTickSeconds + 1)
			t.eq(data.slots["1"], nil, "the Common was hatched and sold")
			t.ok(data.slots["2"] ~= nil, "the Uncommon waits, mature")
			t.eq(count(data.inventory), GameConfig.inventoryCap)
		end,

		["Auto-Harvest replant: toggle off leaves the patch empty"] = function()
			local world = t.server()
			local _, data = world:join(1, {
				cash = 10_000,
				eggs = { Starter = 5 },
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				slots = { ["1"] = grown("Starter", "Uncommon") },
				patches = { ["1"] = { replant = false, egg = "Starter" } },
			})
			world:advance(GameConfig.growthTickSeconds + 1)
			t.eq(count(data.inventory), 1, "hatched")
			t.eq(data.slots["1"], nil, "not replanted")
			t.eq(data.eggs.Starter, 5, "no egg used")
		end,

		["Auto-Harvest replant: toggle on plants from the bag before buying"] = function()
			local world = t.server()
			local _, data = world:join(1, {
				cash = 10_000,
				eggs = { Starter = 1 },
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				slots = { ["1"] = grown("Starter", "Uncommon"), ["2"] = grown("Starter", "Uncommon") },
				patches = { ["1"] = { replant = true, egg = "Starter" }, ["2"] = { replant = true, egg = "Starter" } },
			})
			world:advance(GameConfig.growthTickSeconds + 1)
			t.ok(data.slots["1"] ~= nil and data.slots["2"] ~= nil, "both replanted")
			t.eq(data.eggs.Starter, nil, "the bag's egg went first")
			t.eq(data.cash, 10_000 - 50, "then one was bought at the shop price")
		end,

		["Auto-Harvest replant: a Gem egg is never bought, only replanted from the bag"] = function()
			local world = t.server()
			local _, data = world:join(1, {
				cash = 10_000_000,
				gems = 10_000,
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				slots = { ["1"] = grown("StarterGem", "Rare") },
				patches = { ["1"] = { replant = true, egg = "StarterGem" } },
			})
			world:advance(GameConfig.growthTickSeconds + 1)
			t.eq(data.slots["1"], nil, "no StarterGem in the bag: the patch waits")
			t.eq(data.gems, 10_000, "no Gems spent")
			data.eggs.StarterGem = 1
			world:advance(GameConfig.growthTickSeconds)
			t.ok(data.slots["1"] ~= nil and data.slots["1"].eggId == "StarterGem", "replanted from the bag")
		end,

		["Auto-Harvest replant: an unaffordable patch retries and plants once Cash arrives"] = function()
			local world = t.server()
			local _, data = world:join(1, {
				cash = 0,
				eggs = {},
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				patches = { ["1"] = { replant = true, egg = "Swamp" } },
			})
			world:advance(GameConfig.growthTickSeconds * 3)
			t.eq(data.slots["1"], nil, "no Cash: still empty")
			data.cash = 600
			world:advance(GameConfig.growthTickSeconds)
			t.ok(data.slots["1"] ~= nil and data.slots["1"].eggId == "Swamp", "planted on the next tick")
			t.eq(data.cash, 100)
		end,

		["Auto-Harvest replant: SetReplant needs the pass; hand harvest turns it off, hand planting doesn't"] = function()
			local world = t.server()
			local player, data = world:join(1, { eggs = { Starter = 3 }, grantedStarterEggs = true })
			world:send(player, "SetReplant", 1, true)
			t.eq(data.patches["1"], nil, "no pass: refused")
			data.ownedPasses.AutoHarvest = true
			world:send(player, "SetReplant", 0, true)
			for i = 1, DataService(world).totalSlots(data) do
				t.ok(data.patches[tostring(i)] and data.patches[tostring(i)].replant, "all on")
			end
			world:send(player, "SetReplant", 99, false) -- past the owned patches: ignored
			world:send(player, "SetReplant", 1, "yes") -- not a boolean: ignored
			t.ok(data.patches["1"].replant, "bad arguments change nothing")
			world:send(player, "Plant", 1, "Starter")
			t.ok(data.patches["1"].replant and data.patches["1"].egg == "Starter", "planting keeps the toggle")
			data.ownedPasses.AutoHarvest = nil -- harvest by hand, without the pass harvesting first
			world:advance(Growth.requiredSeconds("Starter", data.slots["1"].rarity) + 1)
			world:send(player, "Harvest", 1)
			t.eq(data.slots["1"], nil, "harvested by hand")
			t.eq(data.patches["1"].replant, false, "emptied by hand: toggle off")
			t.ok(data.patches["2"].replant, "other patches unchanged")
		end,

		["Auto-Harvest offline: the replay stops autoHarvestOfflineHours after leaving"] = function()
			local hours = GameConfig.autoHarvestOfflineHours
			-- The same plot left for the window and for 4 h longer: the same harvests.
			local function away(seconds: number)
				local world = t.server({ seed = 11 })
				local player, data = world:join(1, {
					cash = 1_000_000,
					eggs = { Starter = 2 },
					grantedStarterEggs = true,
					ownedPasses = { AutoHarvest = true },
				})
				world:send(player, "Plant", 1, "Starter")
				world:send(player, "Plant", 2, "Starter")
				world:send(player, "SetReplant", 0, true)
				world:leave(player)
				local left = data.lastSeen
				world:advance(seconds)
				local back, after = world:join(1)
				return after, left, world:received(back, "WelcomeBack")[1][1]
			end
			local inWindow, left, w1 = away(hours * 3600)
			local longer, left2, w2 = away((hours + 4) * 3600)
			t.eq(longer.stats.harvested, inWindow.stats.harvested, "nothing hatched after the window")
			t.ok(inWindow.stats.harvested > 2 * 60, "it ran for the whole window: " .. inWindow.stats.harvested)
			for _, item in longer.inventory do
				t.ok(item.harvestedAt <= left2 + hours * 3600, "kept items hatched inside the window")
			end
			t.eq(w1.autoStopped, false)
			t.eq(w2.autoStopped, true, "Welcome back says it stopped")
			t.ok(left > 0)
		end,

		["Auto-Harvest offline: a 6-Starter plot left 10 h with toggles on ends with more Cash and no Commons"] = function()
			local world = t.server({ seed = 3 })
			local player, data = world:join(1, {
				cash = 300,
				eggs = { Starter = 6 },
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
			})
			for i = 1, 6 do
				world:send(player, "Plant", i, "Starter")
			end
			world:send(player, "SetReplant", 0, true)
			world:leave(player)
			local cash = data.cash
			world:advance(10 * 3600)
			local logged = #world.economy
			local back, after = world:join(1)
			t.ok(after.cash > cash, string.format("Cash up: %d -> %d", cash, after.cash))
			-- Analytics: one event per sku for the whole replay (Sell_Starter_Common, Egg_Starter, the
			-- Almanac's Gems), not one per egg, and the Cash ones add up to the Cash that moved.
			local skus, net = {}, 0
			for i = logged + 1, #world.economy do
				local e = world.economy[i]
				t.ok(not skus[e.flow .. e.sku], "logged once: " .. e.flow .. " " .. e.sku)
				skus[e.flow .. e.sku] = true
				if e.currency == "Cash" then
					net += if e.flow == "Source" then e.amount else -e.amount
				end
			end
			t.ok(#world.economy - logged <= 6, "a handful of events (Almanac Gems too): " .. (#world.economy - logged))
			t.eq(net, after.cash - cash, "logged totals match the Cash moved")
			t.ok(count(after.inventory) > 0, "kept some")
			for _, item in after.inventory do
				t.ok(item.rarity ~= GameConfig.autoSellRarity, "no Commons in the bag")
			end
			local w = world:received(back, "WelcomeBack")[1][1]
			t.ok(w.autoHarvest and w.autoHarvested > 0)
			t.eq(w.autoHarvested, w.autoSold + w.autoKept, "hatched = sold + kept")
			t.eq(w.autoKept, count(after.inventory))
			t.ok(w.autoSold > w.autoKept, "mostly Commons sold")
			t.ok(w.autoSoldValue > 0)
			t.eq(w.waitingCash, 0, "Cash never ran out")
			-- ~1,000 hatches in 8 h: the bag (200) fills with Uncommon+, later ones wait on their patch.
			t.eq(w.autoKept, GameConfig.inventoryCap, "the bag filled")
			t.ok(w.waitingBag >= 1 and w.waitingBag <= 6, "Uncommon+ waiting for bag room: " .. w.waitingBag)
			t.eq(w.autoStopped, true)
		end,

		["Auto-Harvest offline: out of Cash a patch waits; a full bag keeps Uncommon+ on their patches"] = function()
			local world = t.server({ seed = 5 })
			local inventory = {}
			for i = 1, GameConfig.inventoryCap do
				inventory[tostring(i)] = mutant(i, "Starter", "Rare", { pinned = i <= 1 })
			end
			local player, data = world:join(1, {
				cash = 0,
				grantedStarterEggs = true,
				ownedPasses = { AutoHarvest = true },
				inventory = inventory,
				nextItemId = GameConfig.inventoryCap + 1,
				slots = { ["2"] = grown("Swamp", "Epic") },
				patches = {
					["1"] = { replant = true, egg = "Lab" }, -- $5K: never affordable here
					["2"] = { replant = true, egg = "Swamp" },
				},
			})
			world:leave(player)
			world:advance(3600)
			local back, after = world:join(1)
			t.eq(after.slots["1"], nil, "no Cash: patch 1 stays empty")
			t.ok(after.slots["2"] ~= nil, "bag full: the Epic waits on patch 2")
			local w = world:received(back, "WelcomeBack")[1][1]
			t.eq(w.waitingCash, 1)
			t.eq(w.waitingBag, 1)
			t.eq(count(after.inventory), GameConfig.inventoryCap, "nothing sold from the bag")
			t.ok(data.inventory["1"].pinned)
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
			world:send(player, "SetReplant", 0, true)
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
