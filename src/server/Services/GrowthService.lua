--!strict
-- Planting, growing, mutating, watering and harvesting. No per-frame work: each slot stores growth
-- as of updatedAt, and `settle` advances every slot to "now" with shared/Growth.lua, rolling the
-- mutations it crossed on the way. That runs on join (offline catch-up), before any change, and on
-- a short tick so mid-grow mutations pop while the player watches.
--
-- Rolls: rarity + species at planting (hidden until hatch), 10 mutation rolls spread across the
-- grow, size at harvest. The second egg a player ever plants is guaranteed Rare.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local GameConfig = require(Shared.Config.Game)
local Upgrades = require(Shared.Config.Upgrades)
local Mutants = require(Shared.Config.Mutants)
local Daily = require(Shared.Config.Daily)
local Products = require(Shared.Config.Products)
local Costs = require(Shared.Costs)
local GemUpgrades = require(Shared.GemUpgrades)
local ShopRules = require(Shared.ShopRules)
local Growth = require(Shared.Growth)
local AutoHarvest = require(Shared.AutoHarvest)
local WeatherRules = require(Shared.WeatherRules)
local Weather = require(Shared.Config.Weather)
local Rolls = require(Shared.Rolls)
local Onboarding = require(Shared.Onboarding)
local OnboardingConfig = require(Shared.Config.Onboarding)
local Rng = require(Shared.Rng)
local Valuation = require(Shared.Valuation)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local GrowthService = {}

local rng = Rng.new(Random.new():NextInteger(1, 2 ^ 31 - 1))

local GUARANTEED_RARE_PLANT = 2 -- the Nth egg a player ever plants

-- (DataService.luck: passes, potion, Almanac luck; DataService.oddsBonus: the Mutation Odds upgrade.)
local function luck(data: Types.Profile): number
	return DataService.luck(data)
end

local function oddsBonus(data: Types.Profile): number
	return DataService.oddsBonus(data)
end

-- Gem variants hatch the base tier's species.
local function rollSpecies(eggId: string, rarity: string): string
	local bucket = Mutants.buckets[Eggs.baseOf(eggId)][rarity]
	return bucket[rng:integer(1, #bucket)]
end

type MutationEvent = { slotIndex: number, eggId: string, mutation: string }

-- Advances every slot to `now`. Mutation rolls crossed along the way roll at `chanceScale` x
-- the usual chance (default 1; offline: Game.offlineMutationChanceScale; 0 = no rolls, the part
-- of an offline span past the cap). Returns what mutated.
function GrowthService.settle(data: Types.Profile, now: number, chanceScale: number?): { MutationEvent }
	local events = {}
	local speed = DataService.speed(data)
	for key, slot in data.slots do
		if now > slot.updatedAt then
			local required = Growth.slotRequired(slot)
			local grown =
				math.min(Growth.advance(slot.growth, slot.updatedAt, now, DataService.water(data), speed), required)
			local rolls = Growth.rollsCrossed(slot.growth, grown, required)
			-- The scripted first hatch has a fixed outcome: no rolls.
			if chanceScale ~= 0 and not slot.scripted then
				for _ = 1, rolls do
					for _, id in Rolls.rollMutations(rng, slot.mutations, luck(data), oddsBonus(data), chanceScale) do
						table.insert(slot.mutations, id)
						table.insert(events, { slotIndex = tonumber(key) :: number, eggId = slot.eggId, mutation = id })
					end
				end
				slot.lastRollAt = now
			end
			slot.rollsDone += rolls
			slot.growth = grown
			slot.updatedAt = now
		end
	end
	return events
end

-- What a growing egg would sell for right now (size is rolled at harvest, so size 1).
local function worthNow(data: Types.Profile, slot: Types.Slot): number
	return Valuation.sellValue(
		{ tier = Eggs.baseOf(slot.eggId), rarity = slot.rarity, mutations = slot.mutations, size = 1 },
		DataService.cashMultiplier(data)
	)
end

local function announce(player: Player, data: Types.Profile, events: { MutationEvent })
	for _, e in events do
		local slot = data.slots[tostring(e.slotIndex)]
		Net.fire(player, "Mutated", e.slotIndex, e.eggId, e.mutation, if slot then worthNow(data, slot) else 0)
	end
end

local function isMature(slot: Types.Slot): boolean
	return slot.growth >= Growth.slotRequired(slot) - 1e-6
end

local function inventoryCount(data: Types.Profile): number
	local n = 0
	for _ in data.inventory do
		n += 1
	end
	return n
end

local function settleNow(player: Player, data: Types.Profile)
	announce(player, data, GrowthService.settle(data, DataService.now()))
end

-- For other services that change speed or luck (passes): settle, announce, mark changed.
function GrowthService.settleAndAnnounce(player: Player, data: Types.Profile)
	local events = GrowthService.settle(data, DataService.now())
	announce(player, data, events)
	if #events > 0 then
		DataService.changed(player)
	end
end

-- Weather: one roll of the event's mutation on every still-growing egg (once per egg) at the
-- event's chance x luck (WeatherRules.chance). Returns true if anything changed.
function GrowthService.weatherRoll(player: Player, data: Types.Profile, eventId: string, key: string): boolean
	local mutation = (Weather.events :: any)[eventId].mutation
	-- Cheap check first (this runs every second while an event is on): any egg not rolled yet?
	local pending = false
	for _, slot in data.slots do
		if not slot.scripted and not isMature(slot) and not (slot.weatherRolled and slot.weatherRolled[key]) then
			pending = true
			break
		end
	end
	if not pending then
		return false
	end
	local chance = WeatherRules.chance(eventId, luck(data))
	local events = GrowthService.settle(data, DataService.now())
	announce(player, data, events)
	local any = #events > 0
	for k, slot in data.slots do
		if not slot.scripted and not isMature(slot) and not (slot.weatherRolled and slot.weatherRolled[key]) then
			slot.weatherRolled = slot.weatherRolled or {}
			(slot.weatherRolled :: any)[key] = true
			if not table.find(slot.mutations, mutation) and rng:next() < chance then
				table.insert(slot.mutations, mutation)
				any = true
				announce(
					player,
					data,
					{ { slotIndex = tonumber(k) :: number, eggId = slot.eggId, mutation = mutation } }
				)
			end
		end
	end
	if any then
		DataService.changed(player)
	end
	return any
end

-- Plants one egg in an empty slot (at server time `at`, default now). Returns false (with no
-- change) if it can't.
local function plant(player: Player, data: Types.Profile, key: string, eggId: string, at: number?): boolean
	if data.slots[key] or not Eggs.tiers[eggId] or (data.eggs[eggId] or 0) < 1 then
		return false
	end
	local now = at or DataService.now()
	data.eggs[eggId] -= 1
	if data.eggs[eggId] <= 0 then
		data.eggs[eggId] = nil
	end
	data.stats.eggsPlanted += 1
	-- Remember the egg for Auto-Harvest's replant (planting never changes the toggle).
	local patch = data.patches[key]
	if patch then
		patch.egg = eggId
	else
		data.patches[key] = { replant = false, egg = eggId }
	end
	local rarity = if data.stats.eggsPlanted == GUARANTEED_RARE_PLANT
		then "Rare"
		else Rolls.rollRarity(rng, eggId, luck(data))
	data.slots[key] = {
		eggId = eggId,
		rarity = rarity,
		species = rollSpecies(eggId, rarity),
		mutations = {},
		size = 1,
		plantedAt = now,
		growth = 0,
		updatedAt = now,
		rollsDone = 0,
		lastRollAt = now,
		-- The grow ramp (Config/Onboarding.growRamp): the first Starter eggs of every life grow
		-- faster (2026-11-04: every profile, restarting at each rebirth).
		baseGrow = Onboarding.rampSeconds(eggId, data.stats.hatchesThisLife),
		firstRare = if data.stats.eggsPlanted == GUARANTEED_RARE_PLANT then true else nil,
	}
	Analytics.funnel(player, data, "FirstPlant")
	DataService.changed(player)
	return true
end

-- The scripted opening: a new profile's first egg, already growing on its patch, a few seconds
-- from hatching (Config/Onboarding.preplant). Its hatch is the scripted one (harvest below).
-- Counts as the first egg planted, so the player's own first plant is the guaranteed Rare.
function GrowthService.preplant(player: Player, data: Types.Profile)
	local o = data.onboarding
	if not o.active or o.preplanted then
		return
	end
	o.preplanted = true
	local cfg = OnboardingConfig.preplant
	local key = tostring(cfg.slot)
	if data.slots[key] or not Eggs.tiers[cfg.egg] then
		return
	end
	local now = DataService.now()
	local rarity = OnboardingConfig.firstHatch.rarity
	local slot: Types.Slot = {
		eggId = cfg.egg,
		rarity = rarity,
		species = rollSpecies(cfg.egg, rarity),
		mutations = {},
		size = 1,
		plantedAt = now,
		growth = 0,
		updatedAt = now,
		rollsDone = 0,
		lastRollAt = now,
		scripted = "firstHatch",
	}
	slot.growth = math.max(0, Growth.slotRequired(slot) - cfg.secondsLeft)
	data.slots[key] = slot
	data.patches[key] = { replant = false, egg = cfg.egg }
	data.stats.eggsPlanted += 1
	DataService.changed(player)
end

local function onPlant(player: Player, data: Types.Profile, slotIndex: any, eggId: any)
	if not Validate.integer(slotIndex, 1, DataService.totalSlots(data)) or not Validate.string(eggId, 32) then
		return
	end
	if Eggs.tiers[eggId] and (data.eggs[eggId] or 0) < 1 then
		Net.notify(player, "You're out of that egg. Buy more at the Egg Shop!", "info")
		return
	end
	settleNow(player, data)
	plant(player, data, tostring(slotIndex), eggId)
end

-- Almanac milestones: every `every` species discovered pays Gems, once each.
local function almanacMilestone(player: Player, data: Types.Profile)
	local cfg = GameConfig.almanacMilestones
	local found = 0
	for _ in data.almanac do
		found += 1
	end
	local reached = found // cfg.every
	while data.almanacRewards < reached do
		data.almanacRewards += 1
		local at = data.almanacRewards * cfg.every
		local big = cfg.big[at]
		if big then
			-- Real goods at the big milestones: eggs from higher tiers, a permanent luck bonus, or a
			-- bigger Gem prize.
			local parts = {}
			for eggId, count in big.eggs or {} do
				if Eggs.tiers[eggId] then
					data.eggs[eggId] = (data.eggs[eggId] or 0) + count
					table.insert(parts, count .. " " .. Eggs.tiers[eggId].name)
				end
			end
			if big.luck then
				data.almanacLuck += big.luck
				table.insert(parts, string.format("+%d%% luck forever", math.floor(big.luck * 100 + 0.5)))
			end
			if big.gems and EconomyService.addGems(player, data, big.gems, "Gameplay", "Almanac_" .. at) then
				table.insert(parts, string.format("+%d Gems", big.gems))
			end
			Net.notify(player, string.format("%d species! %s", at, table.concat(parts, " + ")), "success")
		elseif EconomyService.addGems(player, data, cfg.gems, "Gameplay", "Almanac_" .. at) then
			Net.notify(player, string.format("%d species discovered! +%d Gems", at, cfg.gems), "success")
		end
	end
end

type HarvestOpts = {
	auto: boolean?, -- by the Auto-Harvest pass (a toast, no cutscene)
	at: number?, -- harvest time (default now)
	quiet: boolean?, -- no per-item messages (offline catch-up sends one summary + the Almanac)
	sold: boolean?, -- sold the moment it's hatched (Auto-Harvest's autoSellRarity): never needs bag room
}

-- Returns the harvested item, or nil (and a reason) if the slot can't be harvested.
local function harvest(player: Player, data: Types.Profile, key: string, opts: HarvestOpts?): (Types.Item?, string?)
	local o: HarvestOpts = opts or {}
	local at, quiet = o.at, o.quiet
	local slot = data.slots[key]
	if not slot or not isMature(slot) then
		return nil, nil
	end
	if not o.sold and inventoryCount(data) >= GameConfig.inventoryCap then
		return nil, "Your bag is full! Sell some at the Sell Pad."
	end
	local id = tostring(data.nextItemId)
	data.nextItemId += 1
	local item: Types.Item = {
		id = id,
		tier = Eggs.baseOf(slot.eggId), -- values, species and the Almanac use the base tier
		egg = slot.eggId,
		rarity = slot.rarity,
		species = slot.species or rollSpecies(slot.eggId, slot.rarity),
		mutations = slot.mutations,
		size = Rolls.rollSize(rng, luck(data)),
		harvestedAt = at or DataService.now(),
	}
	-- The scripted first hatch (Config/Onboarding.firstHatch): a fixed outcome, its value scaled.
	if slot.scripted == "firstHatch" and not data.onboarding.firstHatch then
		local fixed = Onboarding.firstHatchFields()
		item.rarity = fixed.rarity
		item.mutations = fixed.mutations
		item.size = fixed.size
		item.valueScale = fixed.valueScale
		item.scripted = "firstHatch"
		data.onboarding.firstHatch = true
	end
	data.inventory[id] = item
	data.slots[key] = nil
	data.stats.harvested += 1
	data.stats.hatchesThisLife += 1
	Analytics.funnel(player, data, "FirstHatch", DataService.secondsSinceJoin(player))

	-- Almanac: first sighting, count, biggest size.
	local speciesId = item.species :: string
	local entry = data.almanac[speciesId]
	local isNew = entry == nil
	if not entry then
		entry = { n = 0, first = item.harvestedAt, best = 0 }
		data.almanac[speciesId] = entry
	end
	entry.n += 1
	entry.best = math.max(entry.best, item.size)
	if item.scripted == "firstHatch" then
		entry.firstHatch = true -- the Almanac card wears the FIRST HATCH BONUS ribbon
	end
	Analytics.hatch(player, item)
	-- Onboarding: the Starter Bundle's offer window starts on the reveal of the first real Rare
	-- (the guaranteed 2nd egg), not on join; once.
	local offer = nil
	local ob = data.onboarding
	if slot.firstRare and ob.active and not ob.bundle and not data.bundleBought then
		ob.bundle = true
		data.bundleOfferEndsAt = (at or DataService.now()) + Products.robux.StarterBundle.offerSeconds
		offer = "StarterBundle"
	end
	if isNew then
		almanacMilestone(player, data)
	end
	if quiet then
		return item, nil
	end
	Net.fire(player, "Almanac", { [speciesId] = entry })
	Net.fire(
		player,
		"Harvested",
		item,
		Valuation.sellValue(item, DataService.cashMultiplier(data)),
		tonumber(key),
		isNew,
		o.auto == true,
		o.sold == true,
		offer
	)
	return item, nil
end

-- A patch emptied by hand turns its replant toggle off.
local function clearReplant(data: Types.Profile, key: string)
	local patch = data.patches[key]
	if patch then
		patch.replant = false
	end
end

local function onHarvest(player: Player, data: Types.Profile, slotIndex: any)
	if not Validate.integer(slotIndex, 1, DataService.totalSlots(data)) then
		return
	end
	settleNow(player, data)
	local item, reason = harvest(player, data, tostring(slotIndex))
	if item then
		clearReplant(data, tostring(slotIndex))
	end
	if reason then
		Net.notify(player, reason, "error")
	end
	DataService.changed(player)
end

-- Auto-Harvest's replant (patches with the toggle on): the same egg, from the bag of eggs if there
-- is one, else bought with Cash at the shop price when the player can; Gem and limited eggs are
-- never bought (those patches replant from the bag only). Returns true if it planted.
local function replant(player: Player, data: Types.Profile, key: string, eggId: string, at: number?): boolean
	if (data.eggs[eggId] or 0) < 1 then
		local ok = ShopRules.canBuy(eggId, 1, {
			rebirths = data.rebirths,
			totalCashEarned = data.stats.totalCashEarned,
			cash = data.cash,
			gems = data.gems,
			paidRandomRestricted = true, -- Gem eggs are never bought automatically
		})
		local currency, price = ShopRules.price(eggId, 1)
		if
			not ok
			or currency ~= "Cash"
			or not EconomyService.spendCash(player, data, price, "Shop", "Egg_" .. eggId)
		then
			return false
		end
		data.eggs[eggId] = (data.eggs[eggId] or 0) + 1
		data.stats.eggsBought += 1
	end
	return plant(player, data, key, eggId, at)
end

-- Auto-Harvest pass: hatch every mature egg (no cutscene, just a toast). One of
-- Game.autoSellRarity is sold at once (EconomyService.sellItem: logged, counted as earned; never a
-- pinned one), needing no bag room; the rest go to the bag while it has room, else wait mature on
-- their patch. Then each empty patch with its replant toggle on plants its egg again (see
-- replant); toggle off leaves it empty. `at`/`quiet` are for the offline catch-up. Returns how
-- many it harvested; `summary` (offline catch-up) adds up what it did.
type AutoSummary = { harvested: number, sold: number, soldValue: number, kept: number }

local function autoHarvest(
	player: Player,
	data: Types.Profile,
	at: number?,
	quiet: boolean?,
	summary: AutoSummary?
): number
	local harvested, soldCount, soldValue = 0, 0, 0
	local keys = {}
	for key, slot in data.slots do
		if isMature(slot) then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	for _, key in keys do
		local sell = AutoHarvest.decide(data.slots[key].rarity, inventoryCount(data), GameConfig.inventoryCap)
		if sell == "wait" then
			continue -- bag full: it waits, mature, on its patch
		end
		local item = harvest(player, data, key, { auto = true, at = at, quiet = quiet, sold = sell == "sell" })
		if not item then
			continue
		end
		harvested += 1
		if sell == "sell" and not item.pinned then
			local value = EconomyService.sellItem(player, data, item.id)
			if value then
				soldCount += 1
				soldValue += value
			end
		end
	end
	-- Every empty patch with its toggle on gets its egg back (just harvested, or still waiting for
	-- Cash or an egg: it retries on each pass). Toggle off: it stays empty.
	for i = 1, DataService.totalSlots(data) do
		local key = tostring(i)
		local patch = data.patches[key]
		if patch and patch.replant and patch.egg and not data.slots[key] then
			replant(player, data, key, patch.egg, at)
		end
	end
	if summary then
		summary.harvested += harvested
		summary.sold += soldCount
		summary.soldValue += soldValue
		summary.kept += harvested - soldCount
	end
	if soldCount > 0 and not quiet then
		Net.notify(
			player,
			string.format(
				"Auto-sold %d %s for %s",
				soldCount,
				if soldCount == 1 then GameConfig.autoSellRarity else GameConfig.autoSellRarity .. "s",
				Format.cash(soldValue)
			),
			"success"
		)
	end
	if harvested > 0 then
		DataService.changed(player)
	end
	return harvested
end

-- The Auto-Harvest replant toggle of one owned patch, or (slotIndex 0) of every owned patch.
local function onSetReplant(player: Player, data: Types.Profile, slotIndex: any, on: any)
	local total = DataService.totalSlots(data)
	if not Validate.integer(slotIndex, 0, total) or not Validate.boolean(on) or not data.ownedPasses.AutoHarvest then
		return
	end
	local from, to = if slotIndex == 0 then 1 else slotIndex, if slotIndex == 0 then total else slotIndex
	for i = from, to do
		local key = tostring(i)
		local patch = data.patches[key]
		if patch then
			patch.replant = on
		else
			data.patches[key] = { replant = on }
		end
	end
	DataService.changed(player)
end

local function onHarvestAll(player: Player, data: Types.Profile)
	settleNow(player, data)
	local count, value, reason = 0, 0, nil
	for key in table.clone(data.slots) do
		local item, why = harvest(player, data, key)
		if item then
			clearReplant(data, key)
			count += 1
			value += Valuation.sellValue(item, DataService.cashMultiplier(data))
		end
		reason = reason or why
	end
	if count > 1 then
		Net.notify(player, string.format("Hatched %d mutants worth %s", count, Format.cash(value)), "success")
	end
	if reason then
		Net.notify(player, reason, "error")
	end
	DataService.changed(player)
end

-- Luck Potion: Gems for Products.gems.LuckPotion.luck x luck on rarity, mutations and size for
-- its duration (stacks time). Not sold where paid random items / paid odds are restricted.
local function onBuyPotion(player: Player, data: Types.Profile)
	local potion = Products.gems.LuckPotion
	if not ShopRules.canBuyPotion(DataService.paidRandomRestricted[player] ~= false) then
		Net.notify(player, "Luck Potions aren't available in your region", "info")
		return
	end
	-- Settle first: rolls already due use the old luck.
	GrowthService.settleAndAnnounce(player, data)
	if not EconomyService.spendGems(player, data, potion.cost, "Shop", "LuckPotion") then
		Net.notify(player, string.format("Need %d Gems for a Luck Potion", potion.cost), "info")
		return
	end
	local now = DataService.now()
	data.potionUntil = math.max(now, data.potionUntil) + potion.durationSeconds
	Net.notify(player, string.format("Luck Potion! %dx luck for 30 min", potion.luck), "success")
	DataService.changed(player)
end

-- Gems to finish every growing egg now (shared formula, so the client shows the same price).
function GrowthService.skipCost(data: Types.Profile): number
	local now = DataService.now()
	local speed = DataService.speed(data)
	local total = 0
	for _, slot in data.slots do
		local required = Growth.slotRequired(slot)
		local left = Growth.secondsRemaining(slot.growth, required, now, DataService.water(data), speed)
		total += Costs.skip(left, Products.gems.SkipTimer.costPer10Minutes)
	end
	return total
end

-- Skip Timer: finish every growing egg now for Gems. The mutation rolls the skipped time would
-- have made still happen, so skipping never costs you a mutation.
local function onSkipTimers(player: Player, data: Types.Profile)
	GrowthService.settleAndAnnounce(player, data)
	local cost = GrowthService.skipCost(data)
	if cost <= 0 then
		return
	end
	if not EconomyService.spendGems(player, data, cost, "Shop", "SkipTimer") then
		Net.notify(player, string.format("Need %d Gems to finish these now", cost), "info")
		return
	end
	local now = DataService.now()
	local events = {}
	for key, slot in data.slots do
		local required = Growth.slotRequired(slot)
		if slot.growth < required then
			local rolls = Growth.rollsCrossed(slot.growth, required, required)
			for _ = 1, rolls do
				for _, id in Rolls.rollMutations(rng, slot.mutations, luck(data), oddsBonus(data)) do
					table.insert(slot.mutations, id)
					table.insert(events, { slotIndex = tonumber(key) :: number, eggId = slot.eggId, mutation = id })
				end
			end
			slot.rollsDone += rolls
			slot.growth = required
			slot.updatedAt = now
			slot.lastRollAt = now
		end
	end
	announce(player, data, events)
	Net.notify(player, "Done! Your eggs are ready to hatch", "success")
	DataService.changed(player)
end

-- Cash upgrades: growth speed and mutation odds (5 levels each, reset on rebirth).
local function onBuyUpgrade(player: Player, data: Types.Profile, kind: any)
	if kind ~= "growthSpeed" and kind ~= "mutationOdds" then
		return
	end
	local cost = Costs.upgrade(kind, data.upgrades[kind], data.rebirths)
	if not cost then
		return
	end
	-- Settle at the old speed/odds before the upgrade applies.
	GrowthService.settleAndAnnounce(player, data)
	if not EconomyService.spendCash(player, data, cost, "Shop", "Upgrade_" .. kind) then
		return
	end
	data.upgrades[kind] += 1
	Net.notify(player, if kind == "growthSpeed" then "Growth speed upgraded!" else "Mutation odds upgraded!", "success")
	DataService.changed(player)
end

-- Gem upgrades (shared/GemUpgrades): Pen Slots, Permanent Luck, Offline Mutations. Kept through
-- rebirth; not random, so not policy-gated. EconomyService takes the Gems (sink GemUpgrade_<kind>).
local function onBuyGemUpgrade(player: Player, data: Types.Profile, kind: any)
	if not Validate.string(kind, 16) or not table.find(GemUpgrades.order, kind) then
		return
	end
	local level = GemUpgrades.level(data.gemUpgrades, kind)
	local cost = GemUpgrades.cost(kind, level, data.rebirths, data.ownedPasses.OfflineMutations == true)
	if not cost then
		return
	end
	-- Settle first: rolls already due use the old luck.
	GrowthService.settleAndAnnounce(player, data)
	if not EconomyService.spendGems(player, data, cost, "Shop", "GemUpgrade_" .. kind) then
		return
	end
	data.gemUpgrades[kind] = level + 1
	Net.notify(
		player,
		if kind == "penSlots"
			then string.format("Your pen holds %d now!", DataService.penCapacity(data))
			elseif kind == "luck" then "Permanent luck upgraded!"
			else "Offline mutations last longer!",
		"success"
	)
	DataService.changed(player)
end

-- Offline catch-up, run at join. Pays the offline pen income (from the pen as you left it), then
-- replays the time away: with Auto-Harvest, every pass in time order (AutoHarvest.run: hatch, sell
-- Commons, keep the rest while the bag has room, replant toggled patches from the bag or with Cash)
-- for at most Game.autoHarvestOfflineHours; then grows everything to now. Mutation rolls run only
-- for the first offline cap seconds away (the whole time with the Offline Mutations pass; longer
-- with the Gem upgrade), including on eggs replanted while away.
local function catchUp(player: Player, data: Types.Profile)
	local now = DataService.now()
	local away = if data.lastSeen > 0 then now - data.lastSeen else 0

	-- Offline pen income: the offline rate for the whole time away (no cap).
	local earned = 0
	if away > 0 then
		earned = math.floor(DataService.penIncome(data, true) * away / 60)
		if earned <= 0 or not EconomyService.addCash(player, data, earned, "Gameplay", "OfflineIncome") then
			earned = 0
		end
	end

	local capAt = if data.lastSeen > 0 and not data.ownedPasses.OfflineMutations
		then data.lastSeen + GemUpgrades.offlineCap(GemUpgrades.level(data.gemUpgrades, "offline"))
		else math.huge
	local events = {}
	local function settleTo(at: number)
		local rolled
		-- Offline rolls run at a share of the online chance, and stop at the cap.
		local scale = GameConfig.offlineMutationChanceScale
		if at > capAt then
			rolled = GrowthService.settle(data, capAt, scale) -- slots planted after the cap are skipped here
			GrowthService.settle(data, at, 0)
		else
			rolled = GrowthService.settle(data, at, scale)
		end
		table.move(rolled, 1, #rolled, #events + 1, events)
	end

	local summary: AutoSummary = { harvested = 0, sold = 0, soldValue = 0, kept = 0 }
	local waitingCash, waitingBag = 0, 0
	local auto = away > 0 and data.ownedPasses.AutoHarvest == true
	if auto then
		local plot = { slots = data.slots, water = DataService.water(data), speed = DataService.speed(data) }
		local stop = AutoHarvest.windowEnd(data.lastSeen, now)
		Analytics.beginBatch(player) -- one economy event per sku, not one per egg
		AutoHarvest.run(plot, data.lastSeen, stop, function(at)
			settleTo(at)
			return autoHarvest(player, data, at, true, summary)
		end)
		Analytics.flush(player)
		-- Where the replay left the plot: toggled patches it couldn't replant (no Cash, or a Gem
		-- egg it won't buy) and eggs waiting, mature, for bag room.
		settleTo(stop)
		local bagFull = inventoryCount(data) >= GameConfig.inventoryCap
		for i = 1, DataService.totalSlots(data) do
			local key = tostring(i)
			local patch, slot = data.patches[key], data.slots[key]
			if not slot and patch and patch.replant and patch.egg then
				waitingCash += 1
			elseif slot and bagFull and isMature(slot) and slot.rarity ~= GameConfig.autoSellRarity then
				waitingBag += 1
			end
		end
	end
	settleTo(now)
	local capped = now > capAt and next(data.slots) ~= nil

	-- "Welcome back" summary after a real break.
	if away >= Daily.welcomeBackSeconds then
		local ready = 0
		for _, slot in data.slots do
			if isMature(slot) then
				ready += 1
			end
		end
		Net.fire(player, "WelcomeBack", {
			away = away,
			ready = ready,
			mutations = #events,
			capped = capped,
			earned = earned,
			autoHarvest = auto,
			autoHarvested = summary.harvested,
			autoSold = summary.sold,
			autoSoldValue = summary.soldValue,
			autoKept = summary.kept,
			waitingCash = waitingCash,
			waitingBag = waitingBag,
			autoStopped = auto and away > GameConfig.autoHarvestOfflineHours * 3600,
			capHours = if capAt == math.huge then nil else (capAt - data.lastSeen) / 3600,
		})
	end
end

function GrowthService.Init()
	-- Settle before release so the saved growth and lastSeen line up; watering never runs offline
	-- (the boost ends and nobody stands on the pad).
	DataService.onRelease(function(_player, data)
		local now = DataService.now()
		GrowthService.settle(data, now)
		data.wateredUntil = math.min(data.wateredUntil, now)
		data.onPad = false
	end)
end

function GrowthService.Start()
	DataService.Loaded:Connect(function(player, data)
		catchUp(player, data)
		Analytics.funnel(player, data, "Joined")
		Net.fire(player, "Almanac", data.almanac)
		DataService.changed(player)
	end)

	Net.on("Plant", onPlant)
	Net.on("Harvest", onHarvest)
	Net.on("HarvestAll", onHarvestAll)
	Net.on("BuyPotion", onBuyPotion)
	Net.on("SkipTimers", onSkipTimers)
	Net.on("BuyUpgrade", onBuyUpgrade)
	Net.on("BuyGemUpgrade", onBuyGemUpgrade)
	Net.on("SetReplant", onSetReplant)

	while true do
		task.wait(GameConfig.growthTickSeconds)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data and next(data.slots) then
				-- Clients compute growth from the last attributes; only resend when something mutated
				-- or an egg just matured (it stops counting in the farm's $/min).
				local wasReady = 0
				for _, slot in data.slots do
					if isMature(slot) then
						wasReady += 1
					end
				end
				local events = GrowthService.settle(data, DataService.now())
				local ready = 0
				for _, slot in data.slots do
					if isMature(slot) then
						ready += 1
					end
				end
				if #events > 0 then
					announce(player, data, events)
				end
				if #events > 0 or ready ~= wasReady then
					DataService.changed(player)
				end
			end
			-- Auto-Harvest also runs on an empty plot: toggled patches retry their replant.
			if data and data.ownedPasses.AutoHarvest then
				autoHarvest(player, data)
			end
		end
	end
end

return GrowthService
