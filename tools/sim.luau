-- Headless economy simulator. Plays the loop with the real shared math and config,
-- so tuning Config/*.lua and re-running shows the effect immediately.
--
--   lune run tools/sim                         pacing report for the current config
--   lune run tools/sim -- --runs 50 --hours 1.5 --days 30
--
-- The bot: waters every 30s while online, sells everything at once, plants the egg with the
-- best expected profit per minute it can afford, buys the cheapest upgrade whenever it costs
-- under a quarter of its Cash, and rebirths the moment it can. Offline it does nothing unless
-- it owns Auto-Harvest. Weather, the pen and Gems are ignored (they only add upside).

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

---------------------------------------------------------------------------- options

local opts = {
	runs = 20,
	hours = 1.5,
	days = 30,
	rebirths = 10,
	first = false,
	labCost = nil :: number?,
	firstCost = nil :: number?,
}
do
	local args = process.args
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--" then
			-- separator passed through by `lune run tools/sim -- ...`
		elseif a == "--first" then
			opts.first = true -- only the time to Rebirth 1
		elseif a == "--first-cost" then
			opts.firstCost = tonumber(args[i + 1]) -- try a Rebirth 1 cost without editing Config
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

type Slot = { tier: string, rarity: string, mutations: { string }, growth: number, required: number, mature: boolean }

type Player = {
	rng: any,
	passes: { [string]: boolean },
	cash: number,
	rebirths: number,
	slotCount: number,
	slots: { [number]: Slot },
	growthLevel: number,
	oddsLevel: number,
	pending: number, -- value harvested offline by Auto-Harvest, sold on return
	pendingCount: number,
	earned: number, -- lifetime Cash earned (unlocks Lab at Rebirth 0)
	leftAt: number,
	-- stats
	rebirthAt: { number }, -- time (s) each rebirth happened
	activeAt: { number }, -- active seconds when each rebirth happened
	activeSeconds: number,
}

local function luckOf(p: Player): number
	return if p.passes.Luck2x then 2 else 1
end

local function baseSlots(p: Player): number
	return Upgrades.slots.base + (if p.passes.PlotSlots10 then 10 else 0)
end

local function newPlayer(seed: number, passes: { [string]: boolean }): Player
	local p = {
		rng = Rng.new(seed),
		passes = passes,
		cash = GameConfig.startingCash,
		rebirths = 0,
		slotCount = 0,
		slots = {},
		growthLevel = 0,
		oddsLevel = 0,
		pending = 0,
		pendingCount = 0,
		earned = 0,
		leftAt = 0,
		rebirthAt = {},
		activeAt = {},
		activeSeconds = 0,
	}
	p.slotCount = baseSlots(p)
	-- starting eggs are planted straight away
	local i = 1
	for eggId, count in GameConfig.startingEggs do
		for _ = 1, count do
			local rarity = Rolls.rollRarity(p.rng, eggId, luckOf(p))
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
	p.cash -= Eggs.tiers[tierId].cost
	local rarity = Rolls.rollRarity(p.rng, tierId, luckOf(p))
	p.slots[index] = {
		tier = tierId,
		rarity = rarity,
		mutations = {},
		growth = 0,
		required = Growth.requiredSeconds(tierId, rarity),
		mature = false,
	}
end

local function harvestValue(p: Player, slot: Slot): number
	local size = Rolls.rollSize(p.rng, luckOf(p))
	return Valuation.sellValue(
		{ tier = slot.tier, rarity = slot.rarity, mutations = slot.mutations, size = size },
		cashMultiplier(p)
	)
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

-- Expected Cash/min with every slot on the best unlocked tier, actively watered.
local function fullRate(p: Player): number
	local id = bestTier(p, math.huge)
	if not id then
		return 0
	end
	local value, time = eggEV(id, luckOf(p), Upgrades.mutationOdds.bonusPerLevel * p.oddsLevel)
	local speed = Growth.speed(p.growthLevel, p.passes.GrowthSpeed2x == true) * GameConfig.waterMultiplier
	return p.slotCount * (value * cashMultiplier(p) - Eggs.tiers[id].cost) / (time / speed) * 60
end

local function doRebirth(p: Player, now: number)
	p.rebirths += 1
	p.rebirthAt[p.rebirths] = now
	p.activeAt[p.rebirths] = p.activeSeconds
	p.cash = GameConfig.startingCash
	p.slotCount = baseSlots(p)
	p.slots = {}
	p.growthLevel = 0
	p.oddsLevel = 0
end

local function buyUpgrades(p: Player)
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
			return
		end
		p.cash -= pick.cost
		pick.apply()
	end
end

-- One step of `dt` seconds.
local function step(p: Player, now: number, dt: number, online: boolean, rebirthCost: (number) -> number)
	local luck = luckOf(p)
	local oddsBonus = Upgrades.mutationOdds.bonusPerLevel * p.oddsLevel
	local speed = Growth.speed(p.growthLevel, p.passes.GrowthSpeed2x == true)
		* (if online then GameConfig.waterMultiplier else 1)
	local rollsAllowed = online or p.passes.OfflineMutations or (now - p.leftAt) <= GameConfig.offlineMutationCap

	for _, slot in p.slots do
		if not slot.mature then
			local before = slot.growth
			slot.growth += speed * dt
			if rollsAllowed then
				for _ = 1, Growth.rollsCrossed(before, slot.growth, slot.required) do
					for _, id in Rolls.rollMutations(p.rng, slot.mutations, luck, oddsBonus) do
						table.insert(slot.mutations, id)
					end
				end
			end
			slot.mature = slot.growth >= slot.required
		end
	end

	if online then
		p.activeSeconds += dt
		for i, slot in p.slots do
			if slot.mature then
				local value = harvestValue(p, slot)
				p.cash += value
				p.earned += value
				p.slots[i] = nil
			end
		end
		if p.cash >= rebirthCost(p.rebirths) then
			doRebirth(p, now)
			return
		end
		buyUpgrades(p)
		for i = 1, p.slotCount do
			if not p.slots[i] then
				local id = bestTier(p, p.cash)
				if not id then
					break
				end
				plant(p, i, id)
			end
		end
	elseif p.passes.AutoHarvest then
		for i, slot in p.slots do
			if slot.mature and p.pendingCount < GameConfig.inventoryCap then
				p.pending += harvestValue(p, slot)
				p.pendingCount += 1
				p.slots[i] = nil
				if p.cash >= Eggs.tiers[slot.tier].cost then
					plant(p, i, slot.tier)
				end
			end
		end
	end
end

local function login(p: Player)
	p.cash += p.pending
	p.earned += p.pending
	p.pending = 0
	p.pendingCount = 0
end

-- Plays `days` days of `hoursPerDay` active play (one session a day) and returns the player.
local function playDays(seed: number, passes, hoursPerDay: number, days: number, maxRebirths: number, rebirthCost)
	local p = newPlayer(seed, passes)
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
	{ name = "Payer (2x Luck + Auto-Harvest)", passes = { Luck2x = true, AutoHarvest = true } },
}

if opts.labCost then
	Eggs.tiers.Lab.cost = opts.labCost
end
if opts.firstCost then
	harness.require(shared .. "/Config/Rebirths").firstCost = opts.firstCost
end

print(
	string.format(
		"Mutant Farm pacing — %d runs, %.1f active hours/day, up to %d days\n",
		opts.runs,
		opts.hours,
		opts.days
	)
)

-- First session: active minutes to the first rebirth.
do
	local times = {}
	for run = 1, opts.runs do
		local p = playDays(run, {}, 24, 1, 1, costTable)
		table.insert(times, p.activeAt[1] or math.huge)
	end
	print(
		string.format(
			"First rebirth (free, continuous active play): %.0f min median  [target 35–45]\n",
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
		local p = playDays(run * 31, scenario.passes, opts.hours, opts.days, opts.rebirths, costTable)
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
				hours(median(reachedActive[r]))
			)
		)
	end
	print()
end
print("Targets: Rebirth 4 on day 3–4 free / day 1 paying; Rebirth 10 in ~3 weeks free / ~1 week paying.")
