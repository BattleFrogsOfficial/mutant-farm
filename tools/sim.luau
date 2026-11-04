-- Headless economy simulator. Plays the loop with the real shared math and config,
-- so tuning Config/*.lua and re-running shows the effect immediately.
--
--   lune run tools/sim                         pacing report for the current config
--   lune run tools/sim -- --runs 50 --hours 1.5 --days 30
--
-- The bot: stands on its water pad while online and taps a share (`--taps`, default every one) of
-- the growth circle's boosts, sells everything at once (Sell All also sells the
-- pen's auto-fill, so its pen stays empty), plants the egg with the best expected profit per
-- minute it can afford, buys the cheapest upgrade whenever it costs under a quarter of its Cash,
-- and rebirths the moment it can (the bag outside the pen is sold first and counted as earned;
-- the pen stays). Offline nothing is harvested (eggs wait, mature, for the next session). Weather
-- and Gems are ignored.
--
--   --pen keep   a keeper instead: pins its Game.penDisplayCount most valuable mutants (a better
--                one replaces the worst, which is sold). The pen pays penIncomePerMinute of base
--                value x the rebirth multiplier online and penIncomePerMinuteOffline offline.

local process = require("@lune/process")
local harness = require("./harness")

local shared = "src/shared"
local Eggs = harness.require(shared .. "/Config/Eggs")
local Upgrades = harness.require(shared .. "/Config/Upgrades")
local GameConfig = harness.require(shared .. "/Config/Game")
local Rng = harness.require(shared .. "/Rng")
local Rolls = harness.require(shared .. "/Rolls")
local Growth = harness.require(shared .. "/Growth")
local Valuation = harness.require(shared .. "/Valuation")
local Costs = harness.require(shared .. "/Costs")
local ShopRules = harness.require(shared .. "/ShopRules")
local Format = harness.require(shared .. "/Format")
local AutoHarvest = harness.require(shared .. "/AutoHarvest")
local Watering = harness.require(shared .. "/Watering")
local Onboarding = harness.require(shared .. "/Onboarding")
local Weather = harness.require(shared .. "/Weather")
local WeatherRules = harness.require(shared .. "/WeatherRules")
local WeatherConfig = harness.require(shared .. "/Config/Weather")
local GemUpgrades = harness.require(shared .. "/GemUpgrades")
local OnboardingConfig = harness.require(shared .. "/Config/Onboarding")

---------------------------------------------------------------------------- options

local opts = {
	runs = 20,
	hours = 1.5,
	days = 30,
	rebirths = 10,
	first = false,
	labCost = nil :: number?,
	firstCost = nil :: number?,
	growth = nil :: number?,
	pen = "sell",
	autoharvest = false,
	all = false,
	onboarding = false,
	passes = nil :: string?,
	taps = 1,
	bank = false,
	max = false,
}
do
	local args = process.args
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--" then
			-- separator passed through by `lune run tools/sim -- ...`
		elseif a == "--autoharvest" then
			opts.autoharvest = true -- add a paying + Auto-Harvest scenario (toggles on, sells Commons)
		elseif a == "--passes" then
			-- a custom scenario: comma-separated pass ids ("Luck2x,VIP"; "none" = free)
			opts.passes = args[i + 1]
			i += 1
		elseif a == "--onboarding" then
			-- the scripted opening (Config/Onboarding): a pre-planted egg, the scripted $320 first
			-- hatch, the guaranteed Rare 2nd egg, the grow ramp; reports and asserts its first 5 min
			opts.onboarding = true
		elseif a == "--bank" then
			-- add a free bot that hoards its mutants and sells only when that makes a rebirth
			opts.bank = true
		elseif a == "--max" then
			-- add the max bot: every pass, every Gem upgrade, hourly weather, 5 straight hours
			opts.max = true
		elseif a == "--all" then
			opts.all = true -- add a scenario that owns every pass
		elseif a == "--first" then
			opts.first = true -- only the time to Rebirth 1
		elseif a == "--first-cost" then
			opts.firstCost = tonumber(args[i + 1]) -- try a Rebirth 1 cost without editing Config
			i += 1
		elseif a == "--growth" then
			opts.growth = tonumber(args[i + 1]) -- try a rebirth cost multiplier without editing Config
			i += 1
		elseif a == "--taps" then
			-- share of online time under a growth boost: 1 = taps every boost (perfect), 0 = only
			-- stands on the water pad
			opts.taps = tonumber(args[i + 1]) :: number
			i += 1
		elseif a == "--pen" then
			opts.pen = args[i + 1] -- "sell" (default) or "keep"
			i += 1
		elseif a == "--lab-cost" then
			opts.labCost = tonumber(args[i + 1]) -- try a Lab Egg price without editing Config
			i += 1
		elseif a == "--runs" or a == "--hours" or a == "--days" or a == "--rebirths" then
			opts[a:sub(3)] = tonumber(args[i + 1])
			i += 1
		else
			error("unknown option " .. a)
		end
		i += 1
	end
end

---------------------------------------------------------------------------- expected values

local Expected = harness.require(shared .. "/Expected")

local function eggEV(tierId: string, luck: number, oddsBonus: number): (number, number)
	return Expected.egg(tierId, luck, oddsBonus)
end

---------------------------------------------------------------------------- player model

type Slot = {
	tier: string,
	rarity: string,
	mutations: { string },
	growth: number,
	required: number,
	mature: boolean,
	scripted: boolean?, -- onboarding: the scripted first hatch (fixed outcome, no rolls)
	weatherRolled: { [string]: boolean }?, -- weather events that gave it its one roll
}
type Mutant = { tier: string, rarity: string, mutations: { string }, size: number }

type Player = {
	rng: any,
	passes: { [string]: boolean },
	cash: number,
	rebirths: number,
	slotCount: number,
	slots: { [number]: Slot },
	growthLevel: number,
	oddsLevel: number,
	pending: { Mutant }, -- kept offline by Auto-Harvest (Uncommon+), sold (or penned) on return
	lastTier: { [number]: string }, -- the last egg planted on each patch (Auto-Harvest replants it)
	pen: { Mutant }, -- kept mutants: pay pen income, survive rebirth
	earned: number, -- lifetime Cash earned (unlocks Lab at Rebirth 0)
	life: number, -- Cash earned this life (the rebirth requirement since 2026-11-04)
	leftAt: number,
	-- stats
	rebirthAt: { number }, -- time (s) each rebirth happened
	activeAt: { number }, -- active seconds when each rebirth happened
	activeSeconds: number,
	-- onboarding (--onboarding)
	onboarding: boolean,
	bag: { [string]: number }, -- eggs owned but not planted (planting uses these first)
	planted: number, -- eggs planted so far (the 2nd is the guaranteed Rare)
	harvests: number,
	firstSellAt: number?, -- active seconds at the first sale
	eggsBought: number,
	swampSeen: boolean?, -- has had a Swamp egg (the tutorial's last step)
	lastActionAt: number, -- active seconds at the last harvest / plant / purchase
	maxIdleEarly: number, -- the longest wait with nothing to do in the first 5 minutes
	maxIdleEarlyAt: number?, -- when it ended
	bank: boolean, -- --bank: hoards mutants in the bag, sells them only to make a rebirth
	weather: boolean, -- the global weather schedule rolls on its eggs (the max bot)
	gemLuck: number, -- Permanent Luck Gem upgrade (+0.1 a level)
	autoOffline: boolean, -- Auto-Harvest's offline replay (the scenario's `autoOffline`)
}

local function luckOf(p: Player): number
	return (if p.passes.Luck2x then 2 else 1) * (1 + p.gemLuck)
end

local function baseSlots(p: Player): number
	return Upgrades.slots.base + (if p.passes.PlotSlots10 then 10 else 0)
end

local GUARANTEED_RARE_PLANT = 2 -- GrowthService: the Nth egg a player ever plants is Rare

local function newPlayer(seed: number, passes: { [string]: boolean }, onboarding: boolean?): Player
	local p = {
		rng = Rng.new(seed),
		passes = passes,
		cash = GameConfig.startingCash,
		rebirths = 0,
		slotCount = 0,
		slots = {},
		growthLevel = 0,
		oddsLevel = 0,
		pending = {},
		lastTier = {},
		pen = {},
		earned = 0,
		life = 0,
		leftAt = 0,
		rebirthAt = {},
		activeAt = {},
		activeSeconds = 0,
		onboarding = onboarding == true,
		bag = {},
		planted = 0,
		harvests = 0,
		firstSellAt = nil,
		eggsBought = 0,
		swampSeen = nil,
		lastActionAt = 0,
		maxIdleEarly = 0,
		bank = false,
		weather = false,
		gemLuck = 0,
		autoOffline = false,
	}
	p.slotCount = baseSlots(p)
	if p.onboarding then
		-- The pre-planted egg, a few seconds from its scripted hatch, and the bag's eggs.
		local pre = OnboardingConfig.preplant
		local required = Growth.requiredSeconds(pre.egg, OnboardingConfig.firstHatch.rarity)
		p.slots[pre.slot] = {
			tier = pre.egg,
			rarity = OnboardingConfig.firstHatch.rarity,
			mutations = {},
			growth = required - pre.secondsLeft,
			required = required,
			mature = false,
			scripted = true,
		}
		p.planted = 1
		for eggId, count in OnboardingConfig.bag do
			p.bag[eggId] = count
		end
		return p
	end
	-- starting eggs are planted straight away
	local i = 1
	for eggId, count in GameConfig.startingEggs do
		for _ = 1, count do
			local rarity = if p.planted + 1 == GUARANTEED_RARE_PLANT
				then "Rare"
				else Rolls.rollRarity(p.rng, eggId, luckOf(p))
			p.planted += 1
			p.slots[i] = {
				tier = eggId,
				rarity = rarity,
				mutations = {},
				growth = 0,
				required = Growth.requiredSeconds(eggId, rarity),
				mature = false,
			}
			i += 1
		end
	end
	return p
end

local function cashMultiplier(p: Player): number
	return Valuation.cashMultiplier(p.rebirths, p.passes.VIP == true)
end

local function plant(p: Player, index: number, tierId: string)
	if (p.bag[tierId] or 0) > 0 then
		p.bag[tierId] -= 1
	else
		p.cash -= Eggs.tiers[tierId].cost
		p.eggsBought += 1
	end
	p.lastTier[index] = tierId
	p.planted += 1
	local rarity = if p.planted == GUARANTEED_RARE_PLANT then "Rare" else Rolls.rollRarity(p.rng, tierId, luckOf(p))
	local required = Growth.requiredSeconds(tierId, rarity)
	p.slots[index] = {
		tier = tierId,
		rarity = rarity,
		mutations = {},
		growth = 0,
		required = required,
		mature = false,
	}
end

local function harvestMutant(p: Player, slot: Slot): Mutant
	p.harvests += 1
	if slot.scripted then
		-- The scripted first hatch: a fixed outcome with its value scaled (Valuation).
		local f = Onboarding.firstHatchFields()
		return {
			tier = slot.tier,
			rarity = f.rarity,
			mutations = f.mutations,
			size = f.size,
			valueScale = f.valueScale,
		} :: any
	end
	return {
		tier = slot.tier,
		rarity = slot.rarity,
		mutations = slot.mutations,
		size = Rolls.rollSize(p.rng, luckOf(p)),
	}
end

local function sell(p: Player, m: Mutant)
	if p.firstSellAt == nil then
		p.firstSellAt = p.activeSeconds
	end
	local value = Valuation.sellValue(m, cashMultiplier(p))
	p.cash += value
	p.earned += value
	p.life += value
end

-- A new mutant: into the pen if it's worth more than the pen's worst (which is then sold),
-- otherwise sold. Without `--pen keep` everything is sold.
local function keepOrSell(p: Player, m: Mutant)
	if opts.pen == "sell" then
		sell(p, m)
		return
	end
	if #p.pen < GameConfig.penDisplayCount then
		table.insert(p.pen, m)
		return
	end
	local worst, worstValue = 1, math.huge
	for i, kept in p.pen do
		local v = Valuation.sellValue(kept, 1)
		if v < worstValue then
			worst, worstValue = i, v
		end
	end
	if Valuation.sellValue(m, 1) > worstValue then
		sell(p, p.pen[worst])
		p.pen[worst] = m
	else
		sell(p, m)
	end
end

-- Pen income for `dt` seconds at the online or offline rate.
local function penIncome(p: Player, dt: number, online: boolean)
	local rate = if online then GameConfig.penIncomePerMinute else GameConfig.penIncomePerMinuteOffline
	local mult = Valuation.rebirthMultiplier(p.rebirths)
	local perMinute = 0
	for _, m in p.pen do
		perMinute += Valuation.penIncome(m, mult, rate)
	end
	p.cash += perMinute * dt / 60
	p.earned += perMinute * dt / 60
	p.life += perMinute * dt / 60
end

-- Best tier by expected profit per second among unlocked, affordable tiers.
local function bestTier(p: Player, budget: number): string?
	local best, bestRate = nil, -math.huge
	local mult = cashMultiplier(p)
	local oddsBonus = Upgrades.mutationOdds.bonusPerLevel * p.oddsLevel
	for _, id in Eggs.order do
		local tier = Eggs.tiers[id]
		if ShopRules.isUnlocked(id, p.rebirths, p.earned) and tier.cost <= budget then
			local value, time = eggEV(id, luckOf(p), oddsBonus)
			local rate = (value * mult - tier.cost) / time
			if rate > bestRate then
				best, bestRate = id, rate
			end
		end
	end
	return best
end

-- Can the player do anything right now: hatch, plant into an empty patch, or buy a patch or an
-- upgrade? (Growth boosts don't count: they're the waiting itself.)
local function somethingToDo(p: Player): boolean
	local cheapestEgg = math.huge
	for _, id in Eggs.order do
		if ShopRules.isUnlocked(id, p.rebirths, p.earned) then
			cheapestEgg = math.min(cheapestEgg, Eggs.tiers[id].cost)
		end
	end
	local bagged = 0
	for _, n in p.bag do
		bagged += n
	end
	for i = 1, p.slotCount do
		local slot = p.slots[i]
		if slot and slot.mature then
			return true
		elseif not slot and (bagged > 0 or p.cash >= cheapestEgg) then
			return true
		end
	end
	local costs = {
		Costs.slot(p.slotCount + 1, p.rebirths),
		Costs.upgrade("growthSpeed", p.growthLevel, p.rebirths),
		Costs.upgrade("mutationOdds", p.oddsLevel, p.rebirths),
	}
	for _, c in costs do
		if c and p.cash >= c then
			return true
		end
	end
	return false
end

-- Where the onboarding bot is in the tutorial (the same rule the HUD's Next Up uses).
local function tutorialStep(p: Player): string?
	local bagged = 0
	for _, n in p.bag do
		bagged += n
	end
	local empty, growing, swamp = false, 0, false
	for i = 1, p.slotCount do
		local slot = p.slots[i]
		if not slot then
			empty = true
		elseif not slot.mature then
			growing += 1
		end
		if slot and slot.tier == "Swamp" then
			swamp = true
		end
	end
	p.swampSeen = p.swampSeen or swamp
	return Onboarding.tutorialStep({
		harvested = p.harvests,
		sold = if p.firstSellAt then 1 else 0,
		eggsBought = p.eggsBought,
		eggsPlanted = p.planted,
		eggsInBag = bagged,
		emptyPatch = empty,
		growing = growing,
		waters = 1, -- the bot taps from the start
		padVisits = 1,
		slotsBought = p.slotCount - baseSlots(p),
		canBuySlot = Costs.slot(p.slotCount + 1, p.rebirths) ~= nil,
		hasSwamp = p.swampSeen == true,
		tutorialDone = p.swampSeen == true, -- the bot opens the Almanac at once
	})
end

-- Online watering: the pad all the time, and a growth boost (the higher of the two applies) for
-- `opts.taps` of it, at the average of max(pad, offer) over the offers' odds.
-- The bot stands on its pad; a perfect tapper (`--taps 1`) runs the circle's whole cycle (the
-- boost, then the 3-8 s vanish at the pad's 2x), an idler (`--taps 0`) the pad alone.
local function onlineWater(): number
	local pad = GameConfig.water.padMultiplier
	return opts.taps * Watering.cycleRate(pad) + (1 - opts.taps) * pad
end

-- Expected Cash/min with every slot on the best unlocked tier, actively watered.
local function fullRate(p: Player): number
	local id = bestTier(p, math.huge)
	if not id then
		return 0
	end
	local value, time = eggEV(id, luckOf(p), Upgrades.mutationOdds.bonusPerLevel * p.oddsLevel)
	local speed = Growth.speed(p.growthLevel, p.passes.GrowthSpeed2x == true) * onlineWater()
	return p.slotCount * (value * cashMultiplier(p) - Eggs.tiers[id].cost) / (time / speed) * 60
end

local function doRebirth(p: Player, now: number)
	-- The bag outside the pen is sold first (counted as earned, never toward the new life); then
	-- Cash resets.
	for _, m in p.pending do
		sell(p, m)
	end
	p.pending = {}
	p.life = 0
	p.rebirths += 1
	p.rebirthAt[p.rebirths] = now
	p.activeAt[p.rebirths] = p.activeSeconds
	p.cash = GameConfig.startingCash
	p.slotCount = baseSlots(p)
	p.slots = {}
	p.growthLevel = 0
	p.oddsLevel = 0
end

-- Buys upgrades while the cheapest costs under a quarter of the Cash; returns how many.
local function buyUpgrades(p: Player): number
	local bought = 0
	while true do
		local options = {}
		local slotCost = Costs.slot(p.slotCount + 1, p.rebirths)
		if slotCost then
			table.insert(options, {
				cost = slotCost,
				apply = function()
					p.slotCount += 1
				end,
			})
		end
		local g = Costs.upgrade("growthSpeed", p.growthLevel, p.rebirths)
		if g then
			table.insert(options, {
				cost = g,
				apply = function()
					p.growthLevel += 1
				end,
			})
		end
		local o = Costs.upgrade("mutationOdds", p.oddsLevel, p.rebirths)
		if o then
			table.insert(options, {
				cost = o,
				apply = function()
					p.oddsLevel += 1
				end,
			})
		end
		table.sort(options, function(a, b)
			return a.cost < b.cost
		end)
		local pick = options[1]
		if not pick or pick.cost > p.cash * 0.25 then
			return bought
		end
		p.cash -= pick.cost
		pick.apply()
		bought += 1
	end
end

-- Sim time 0 as wall-clock time for the weather schedule (a fixed day, so runs are repeatable).
local SIM_EPOCH = 1_800_000_000

-- One step of `dt` seconds.
local function step(p: Player, now: number, dt: number, online: boolean, rebirthCost: (number) -> number)
	local luck = luckOf(p)
	local oddsBonus = Upgrades.mutationOdds.bonusPerLevel * p.oddsLevel
	local speed = Growth.speed(p.growthLevel, p.passes.GrowthSpeed2x == true) * (if online then onlineWater() else 1)
	local rollsAllowed = online or p.passes.OfflineMutations or (now - p.leftAt) <= GameConfig.offlineMutationCap

	for _, slot in p.slots do
		if not slot.mature then
			local before = slot.growth
			slot.growth += speed * dt
			if rollsAllowed and not slot.scripted then
				for _ = 1, Growth.rollsCrossed(before, slot.growth, slot.required) do
					local scale = if online then 1 else GameConfig.offlineMutationChanceScale
					for _, id in Rolls.rollMutations(p.rng, slot.mutations, luck, oddsBonus, scale) do
						table.insert(slot.mutations, id)
					end
				end
			end
			slot.mature = slot.growth >= slot.required
		end
	end

	-- Hourly global weather (the max bot): each growing egg gets one roll per event.
	if p.weather then
		local e = Weather.scheduleAt(SIM_EPOCH + now)
		if e.active then
			local key = WeatherRules.key("global", e.startsAt)
			local mutation = WeatherConfig.events[e.id].mutation
			local chance = WeatherRules.chance(e.id, luck)
			for _, slot in p.slots do
				if not slot.mature and not slot.scripted and not (slot.weatherRolled and slot.weatherRolled[key]) then
					slot.weatherRolled = slot.weatherRolled or {}
					(slot.weatherRolled :: any)[key] = true
					if not table.find(slot.mutations, mutation) and p.rng:next() < chance then
						table.insert(slot.mutations, mutation)
					end
				end
			end
		end
	end

	penIncome(p, dt, online)
	if online then
		p.activeSeconds += dt
		local actions = 0
		for i, slot in p.slots do
			if slot.mature then
				local m = harvestMutant(p, slot)
				if slot.scripted then
					sell(p, m) -- the scripted first hatch is sold, never kept
				elseif p.bank then
					table.insert(p.pending, m) -- hoarded in the bag
				else
					keepOrSell(p, m)
				end
				p.slots[i] = nil
				actions += 1
			end
		end
		-- The hoarder sells its bag only when that makes the rebirth (earned this life is the
		-- requirement, so the rebirth's own bag sale wouldn't count), when the bag is full, or
		-- when it can't buy an egg for an empty patch.
		if p.bank and #p.pending > 0 then
			local bagValue = 0
			for _, m in p.pending do
				bagValue += Valuation.sellValue(m, cashMultiplier(p))
			end
			local broke = p.cash < Eggs.tiers.Starter.cost and next(p.bag) == nil
			if p.life + bagValue >= rebirthCost(p.rebirths) or #p.pending >= GameConfig.inventoryCap or broke then
				for _, m in p.pending do
					sell(p, m)
				end
				p.pending = {}
			end
		end
		if p.life >= rebirthCost(p.rebirths) then
			doRebirth(p, now)
			return
		end
		actions += buyUpgrades(p)
		-- The onboarding bot follows the tutorial (Onboarding.tutorialStep): Starter eggs until its
		-- "first Swamp egg" step, then one Swamp; its own choices only once the tutorial is done.
		local step = if p.onboarding then tutorialStep(p) else nil
		for i = 1, p.slotCount do
			if not p.slots[i] then
				local bagged = nil
				for eggId, n in p.bag do
					if n > 0 then
						bagged = eggId
					end
				end
				local tutorialEgg = if step == "swamp" then "Swamp" elseif step ~= nil then "Starter" else nil
				if tutorialEgg and Eggs.tiers[tutorialEgg].cost > p.cash and not bagged then
					break
				end
				local id = bagged or tutorialEgg or bestTier(p, p.cash)
				if not id then
					break
				end
				plant(p, i, id)
				actions += 1
			end
		end
		-- The longest stretch with nothing to do in the first 5 minutes (--onboarding asserts it
		-- stays under 45 s): no egg to hatch, no egg you can afford for an empty patch, and no patch or
		-- upgrade you can afford (the bot's own thrift doesn't count as nothing to do).
		if actions > 0 or somethingToDo(p) then
			p.lastActionAt = p.activeSeconds
		elseif p.activeSeconds <= 300 then
			local gap = p.activeSeconds - p.lastActionAt
			if gap > p.maxIdleEarly then
				p.maxIdleEarly = gap
				p.maxIdleEarlyAt = p.activeSeconds
			end
		end
	elseif p.autoOffline and p.passes.AutoHarvest and now - p.leftAt < GameConfig.autoHarvestOfflineHours * 3600 then
		-- Auto-Harvest with every replant toggle on (the server's rules, shared/AutoHarvest):
		-- Commons sold at once, the rest kept while the bag (pen included) has room, else they wait
		-- on their patch; each empty patch rebuys its last egg with Cash when it can.
		for i = 1, p.slotCount do
			local slot = p.slots[i]
			if slot and slot.mature then
				local what = AutoHarvest.decide(slot.rarity, #p.pending + #p.pen, GameConfig.inventoryCap)
				if what == "sell" then
					sell(p, harvestMutant(p, slot))
					p.slots[i] = nil
				elseif what == "keep" then
					table.insert(p.pending, harvestMutant(p, slot))
					p.slots[i] = nil
				end
			end
			local tier = p.lastTier[i]
			if not p.slots[i] and tier and p.cash >= Eggs.tiers[tier].cost then
				plant(p, i, tier)
			end
		end
	end
end

local function login(p: Player)
	if p.bank then
		return -- the hoarder keeps its bag
	end
	for _, m in p.pending do
		keepOrSell(p, m)
	end
	p.pending = {}
end

-- Plays `days` days of `hoursPerDay` active play (one session a day) and returns the player.
-- `onboarding` (default --onboarding): a new profile with the scripted opening.
local function playDays(
	seed: number,
	passes,
	hoursPerDay: number,
	days: number,
	maxRebirths: number,
	rebirthCost,
	onboarding: boolean?,
	setup: ((Player) -> ())?
)
	local p = newPlayer(seed, passes, if onboarding == nil then opts.onboarding else onboarding)
	if setup then
		setup(p)
	end
	local now = 0
	local onlineDt, offlineDt = 2, 30
	for _ = 1, days do
		login(p)
		local sessionEnd = now + hoursPerDay * 3600
		while now < sessionEnd do
			step(p, now, onlineDt, true, rebirthCost)
			now += onlineDt
		end
		p.leftAt = now
		local dayEnd = now + (24 - hoursPerDay) * 3600
		while now < dayEnd do
			step(p, now, offlineDt, false, rebirthCost)
			now += offlineDt
		end
		if p.rebirths >= maxRebirths then
			break
		end
	end
	return p
end

-- Plays one rebirth phase of continuous active play from a fresh reset (Cash = startingCash,
-- base slots, no upgrades); returns active seconds taken and the final full-slot Cash/min.
local function playPhase(seed: number, passes, startRebirths: number, cost: number, limit: number): (number, number)
	local p = newPlayer(seed, passes)
	p.rebirths = startRebirths
	p.slots = {}
	local now = 0
	local rate = 0
	while p.rebirths == startRebirths and now < limit do
		rate = fullRate(p)
		step(p, now, 2, true, function()
			return cost
		end)
		now += 2
	end
	return now, rate
end

---------------------------------------------------------------------------- reports

local function median(list: { number }): number
	table.sort(list)
	if #list == 0 then
		return math.huge
	end
	return list[math.ceil(#list / 2)]
end

local function hours(seconds: number): string
	if seconds == math.huge then
		return "—"
	end
	return string.format("%.1fh", seconds / 3600)
end

local function costTable(r: number): number
	return Costs.rebirth(r)
end

local scenarios = {
	{ name = "Free", passes = {} },
	{ name = "Paying (2x Luck)", passes = { Luck2x = true } },
}
if opts.passes then
	local set = {}
	for id in string.gmatch(opts.passes, "[^,]+") do
		if id ~= "none" then
			set[id] = true
		end
	end
	scenarios = { { name = "Custom (" .. opts.passes .. ")", passes = set } }
end
if opts.all then
	table.insert(scenarios, {
		name = "Everything (every pass: 2x Luck, Auto-Harvest, 1.5x Growth, Offline Mutations, +10 Slots, VIP)",
		passes = {
			Luck2x = true,
			AutoHarvest = true,
			GrowthSpeed2x = true,
			OfflineMutations = true,
			PlotSlots10 = true,
			VIP = true,
		},
	})
end
if opts.autoharvest then
	table.insert(scenarios, {
		name = string.format(
			"Paying + Auto-Harvest (2x Luck, toggles on, Commons sold, %d h offline)",
			GameConfig.autoHarvestOfflineHours
		),
		passes = { Luck2x = true, AutoHarvest = true },
		autoOffline = true,
	})
	if opts.all then
		table.insert(scenarios, {
			name = string.format("Everything + Auto-Harvest offline (%d h a day)", GameConfig.autoHarvestOfflineHours),
			passes = {
				Luck2x = true,
				AutoHarvest = true,
				GrowthSpeed2x = true,
				OfflineMutations = true,
				PlotSlots10 = true,
				VIP = true,
			},
			autoOffline = true,
		})
	end
end

if opts.labCost then
	Eggs.tiers.Lab.cost = opts.labCost
end
if opts.firstCost then
	harness.require(shared .. "/Config/Rebirths").firstCost = opts.firstCost
end
if opts.growth then
	harness.require(shared .. "/Config/Rebirths").costGrowth = opts.growth
end

print(
	string.format(
		"Mutant Farm pacing — %d runs, %.1f active hours/day, up to %d days, pen: %s, online growth x%.2f (water pad + %d%% of boosts tapped)\n",
		opts.runs,
		opts.hours,
		opts.days,
		if opts.pen == "sell" then "sell everything" else "keep the best " .. GameConfig.penDisplayCount,
		onlineWater(),
		math.floor(opts.taps * 100 + 0.5)
	)
)

-- The scripted opening (--onboarding): the first five minutes, asserted, and the first rebirth
-- against the same bot without it (within 5%).
if opts.onboarding then
	local idle, firstSell, withIt, without = {}, {}, {}, {}
	for run = 1, opts.runs do
		local p = playDays(run, {}, 24, 1, 1, costTable, true)
		table.insert(idle, p.maxIdleEarly)
		if process.env.SIM_TRACE then
			print(
				string.format(
					"run %d: longest gap %.0f s, ending at %.0f s",
					run,
					p.maxIdleEarly,
					p.maxIdleEarlyAt or 0
				)
			)
		end
		table.insert(firstSell, p.firstSellAt or math.huge)
		table.insert(withIt, p.activeAt[1] or math.huge)
		table.insert(without, playDays(run, {}, 24, 1, 1, costTable, false).activeAt[1] or math.huge)
	end
	local worstIdle = math.max(table.unpack(idle))
	local worstSell = math.max(table.unpack(firstSell))
	local a, b = median(withIt), median(without)
	local change = (a - b) / b
	print("Onboarding (the scripted opening), free, continuous play:")
	print(
		string.format(
			"  longest wait with nothing to do in the first 5 min: %.0f s worst run, %.0f s median  [<= 45]",
			worstIdle,
			median(table.clone(idle))
		)
	)
	print(string.format("  first sale: %.0f s (worst run)  [< 60]", worstSell))
	print(
		string.format(
			"  first rebirth: %.1f min with it, %.1f min without (%+.1f%%)  [within 5%%]\n",
			a / 60,
			b / 60,
			change * 100
		)
	)
	-- The checks: each reported, and the run fails (exit 1) if any does.
	local checks = {
		{ worstIdle <= 45, "never waits more than 45 s with nothing to do in the first 5 min" },
		{ worstSell < 60, "first sale under 60 s" },
		{ math.abs(change) <= 0.05, "first rebirth within 5% of the same bot without the opening" },
	}
	local failed = false
	for _, c in checks do
		print(string.format("  %s  %s", if c[1] then "PASS" else "FAIL", c[2]))
		failed = failed or not c[1]
	end
	print()
	if failed then
		print("Onboarding checks FAILED (see above).")
		process.exit(1)
	end
end

-- First session: active minutes to the first rebirth.
do
	local times = {}
	for run = 1, opts.runs do
		local p = playDays(run, {}, 24, 1, 1, costTable)
		table.insert(times, p.activeAt[1] or math.huge)
	end
	print(
		string.format(
			"First rebirth (free, continuous active play): %.0f min median  [target 22-30 tapping, 30-60 idle]\n",
			median(times) / 60
		)
	)
	if opts.first then
		return
	end
end

for _, scenario in scenarios do
	local reachedDay, reachedActive = {}, {}
	for r = 1, opts.rebirths do
		reachedDay[r], reachedActive[r] = {}, {}
	end
	for run = 1, opts.runs do
		local p = playDays(run * 31, scenario.passes, opts.hours, opts.days, opts.rebirths, costTable, nil, function(p)
			p.autoOffline = scenario.autoOffline == true
		end)
		for r = 1, opts.rebirths do
			table.insert(reachedDay[r], if p.rebirthAt[r] then p.rebirthAt[r] / 86400 else math.huge)
			table.insert(reachedActive[r], p.activeAt[r] or math.huge)
		end
	end
	print(scenario.name)
	print("  rebirth   cost            day reached   active play")
	for r = 1, opts.rebirths do
		local day = median(reachedDay[r])
		print(
			string.format(
				"  %-9d %-15s %-13s %s",
				r,
				Format.cash(Costs.rebirth(r - 1)),
				if day == math.huge then "not in " .. opts.days .. "d" else string.format("day %d", math.floor(day) + 1),
				if r == 1 and median(reachedActive[r]) < math.huge
					then string.format("%s (%.0f min)", hours(median(reachedActive[r])), median(reachedActive[r]) / 60)
					else hours(median(reachedActive[r]))
			)
		)
	end
	print()
end
-- The hoarder (--bank): keeps its mutants and sells only to make a rebirth. Rebirth gates on Cash
-- earned this life, so banking never chains rebirths: over 7 days it must not beat the default bot.
if opts.bank then
	local bankCount, plainCount = {}, {}
	for run = 1, opts.runs do
		local plain = playDays(run * 31, {}, opts.hours, 7, 99, costTable)
		local bank = playDays(run * 31, {}, opts.hours, 7, 99, costTable, nil, function(p)
			p.bank = true
		end)
		table.insert(plainCount, plain.rebirths)
		table.insert(bankCount, bank.rebirths)
	end
	local b, d = median(bankCount), median(plainCount)
	print("Bank bot (free, hoards mutants, sells only to make a rebirth), 7 days:")
	print(
		string.format(
			"  rebirths: %d median (default bot: %d)  %s\n",
			b,
			d,
			if b <= d then "PASS (<= default)" else "FAIL"
		)
	)
end

-- The max bot (--max): every pass, every Gem upgrade, hourly weather, 5 straight hours of play.
if opts.max then
	local firsts, counts = {}, {}
	local allPasses = {
		Luck2x = true,
		AutoHarvest = true,
		GrowthSpeed2x = true,
		OfflineMutations = true,
		PlotSlots10 = true,
		VIP = true,
	}
	for run = 1, opts.runs do
		local p = playDays(run * 17, allPasses, 5, 1, 99, costTable, nil, function(p)
			p.weather = true
			p.gemLuck = GemUpgrades.luckBonus(#harness.require(shared .. "/Config/Upgrades").gem.luck.costs)
		end)
		table.insert(firsts, p.activeAt[1] or math.huge)
		table.insert(counts, p.rebirths)
	end
	local first = median(firsts)
	print("Max bot (every pass, all Gem upgrades, hourly weather, 5 straight hours):")
	print(
		string.format(
			"  first rebirth at %.0f sim-min  %s; %d rebirths in the 5 h\n",
			first / 60,
			if first > 3600 then "PASS (> 60)" else "FAIL (target > 60)",
			median(counts)
		)
	)
end

print(
	"Targets (2026-11-03): Rebirth 10 in ~20 h of play with every pass (one long session: --all --hours 30 --days 1); free about 3x the play."
)
