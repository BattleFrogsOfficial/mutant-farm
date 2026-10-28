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
local ShopRules = require(Shared.ShopRules)
local Growth = require(Shared.Growth)
local AutoHarvest = require(Shared.AutoHarvest)
local Rolls = require(Shared.Rolls)
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

-- 2x Luck pass x Luck Potion (while active). Rolls.clampLuck caps the total at Game.maxLuck.
local function luck(data: Types.Profile): number
	local pass = if data.ownedPasses.Luck2x then 2 else 1
	local potion = if DataService.now() < data.potionUntil then Products.gems.LuckPotion.luck else 1
	return pass * potion * (1 + data.almanacLuck)
end

local function oddsBonus(data: Types.Profile): number
	return Upgrades.mutationOdds.bonusPerLevel * data.upgrades.mutationOdds
end

-- Gem variants hatch the base tier's species.
local function rollSpecies(eggId: string, rarity: string): string
	local bucket = Mutants.buckets[Eggs.baseOf(eggId)][rarity]
	return bucket[rng:integer(1, #bucket)]
end

type MutationEvent = { slotIndex: number, eggId: string, mutation: string }

-- Advances every slot to `now`. Mutation rolls crossed along the way are applied only if
-- `rollsAllowed` (false for the part of an offline span past the cap). Returns what mutated.
function GrowthService.settle(data: Types.Profile, now: number, rollsAllowed: boolean?): { MutationEvent }
	local events = {}
	local speed = DataService.speed(data)
	for key, slot in data.slots do
		if now > slot.updatedAt then
			local required = Growth.requiredSeconds(slot.eggId, slot.rarity)
			local grown = math.min(Growth.advance(slot.growth, slot.updatedAt, now, data.wateredUntil, speed), required)
			local rolls = Growth.rollsCrossed(slot.growth, grown, required)
			if rollsAllowed ~= false then
				for _ = 1, rolls do
					for _, id in Rolls.rollMutations(rng, slot.mutations, luck(data), oddsBonus(data)) do
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
	return slot.growth >= Growth.requiredSeconds(slot.eggId, slot.rarity) - 1e-6
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

-- Weather: gives a still-growing egg `mutation` (once) with `chance` x luck. Returns true if it did.
function GrowthService.weatherRoll(player: Player, data: Types.Profile, mutation: string, chance: number): boolean
	local events = GrowthService.settle(data, DataService.now())
	announce(player, data, events)
	local any = #events > 0
	for key, slot in data.slots do
		if not isMature(slot) and not table.find(slot.mutations, mutation) then
			if rng:next() < math.min(chance * luck(data), 0.9) then
				table.insert(slot.mutations, mutation)
				any = true
				announce(
					player,
					data,
					{ { slotIndex = tonumber(key) :: number, eggId = slot.eggId, mutation = mutation } }
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
	}
	Analytics.funnel(player, data, "FirstPlant")
	DataService.changed(player)
	return true
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
			-- Real goods at the big milestones: eggs from higher tiers, or a permanent luck bonus.
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
			Net.notify(player, string.format("📖 %d species! %s", at, table.concat(parts, " + ")), "success")
		elseif EconomyService.addGems(player, data, cfg.gems, "Gameplay", "Almanac_" .. at) then
			Net.notify(player, string.format("📖 %d species discovered! +%d Gems", at, cfg.gems), "success")
		end
	end
end

-- Returns the harvested item, or nil (and a reason) if the slot can't be harvested. `at` is the
-- harvest time (default now); `quiet` skips the per-item messages (offline catch-up sends one
-- summary and the full Almanac instead).
local function harvest(
	player: Player,
	data: Types.Profile,
	key: string,
	auto: boolean?,
	at: number?,
	quiet: boolean?
): (Types.Item?, string?)
	local slot = data.slots[key]
	if not slot or not isMature(slot) then
		return nil, nil
	end
	if inventoryCount(data) >= GameConfig.inventoryCap then
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
	data.inventory[id] = item
	data.slots[key] = nil
	data.stats.harvested += 1
	Analytics.funnel(player, data, "FirstHarvest")

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
		auto == true
	)
	return item, nil
end

local function onHarvest(player: Player, data: Types.Profile, slotIndex: any)
	if not Validate.integer(slotIndex, 1, DataService.totalSlots(data)) then
		return
	end
	settleNow(player, data)
	local _, reason = harvest(player, data, tostring(slotIndex))
	if reason then
		Net.notify(player, reason, "error")
	end
	DataService.changed(player)
end

-- Auto-Harvest replants the same egg: one from the bag of eggs if there is one, else it buys one
-- with Cash (never Gems) when the player can. Returns true if it planted.
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

-- Auto-Harvest pass: hatch every mature egg (no cutscene, just a toast) and replant the same egg
-- (see replant) while the bag has room. Stops quietly when the bag is full. `at`/`quiet` are for
-- the offline catch-up. Returns how many it harvested.
local function autoHarvest(player: Player, data: Types.Profile, at: number?, quiet: boolean?): number
	local harvested = 0
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
		local eggId = data.slots[key].eggId
		local item = harvest(player, data, key, true, at, quiet)
		if not item then
			break
		end
		harvested += 1
		if inventoryCount(data) < GameConfig.inventoryCap then
			replant(player, data, key, eggId, at)
		end
	end
	if harvested > 0 then
		DataService.changed(player)
	end
	return harvested
end

local function onHarvestAll(player: Player, data: Types.Profile)
	settleNow(player, data)
	local count, value, reason = 0, 0, nil
	for key in table.clone(data.slots) do
		local item, why = harvest(player, data, key)
		if item then
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
	Net.notify(player, string.format("🍀 Luck Potion! %dx luck for 30 min", potion.luck), "success")
	DataService.changed(player)
end

-- Gems to finish every growing egg now (shared formula, so the client shows the same price).
function GrowthService.skipCost(data: Types.Profile): number
	local now = DataService.now()
	local speed = DataService.speed(data)
	local total = 0
	for _, slot in data.slots do
		local required = Growth.requiredSeconds(slot.eggId, slot.rarity)
		local left = Growth.secondsRemaining(slot.growth, required, now, data.wateredUntil, speed)
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
		local required = Growth.requiredSeconds(slot.eggId, slot.rarity)
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
	Net.notify(player, "⏩ Done! Your eggs are ready to hatch", "success")
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
	Net.notify(
		player,
		if kind == "growthSpeed" then "⚡ Growth speed upgraded!" else "✨ Mutation odds upgraded!",
		"success"
	)
	DataService.changed(player)
end

local function onWater(player: Player, data: Types.Profile)
	local now = DataService.now()
	if now < data.wateredUntil then
		return
	end
	-- Settle at the old speed before the watering window starts.
	settleNow(player, data)
	data.wateredUntil = now + GameConfig.waterDuration
	data.stats.waters += 1
	DataService.changed(player)
end

-- Offline catch-up, run at join. Pays the offline pen income (from the pen as you left it), then
-- replays the time away: with Auto-Harvest, every grow cycle in order (AutoHarvest.run: harvest
-- to the bag, replant, buying eggs with Cash when out); then grows everything to now. Mutation
-- rolls run only for the first offlineMutationCap seconds away (the whole time with the Offline
-- Mutations pass), including on eggs replanted while away.
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
		then data.lastSeen + GameConfig.offlineMutationCap
		else math.huge
	local events = {}
	local function settleTo(at: number)
		local rolled
		if at > capAt then
			rolled = GrowthService.settle(data, capAt) -- slots planted after the cap are skipped here
			GrowthService.settle(data, at, false)
		else
			rolled = GrowthService.settle(data, at)
		end
		table.move(rolled, 1, #rolled, #events + 1, events)
	end

	local autoHarvested = 0
	if away > 0 and data.ownedPasses.AutoHarvest then
		local plot = { slots = data.slots, wateredUntil = data.wateredUntil, speed = DataService.speed(data) }
		autoHarvested = AutoHarvest.run(plot, data.lastSeen, now, function(at)
			settleTo(at)
			return autoHarvest(player, data, at, true)
		end)
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
			autoHarvested = autoHarvested,
		})
	end
end

function GrowthService.Init()
	-- Settle before release so the saved growth and lastSeen line up; watering never runs offline.
	DataService.onRelease(function(_player, data)
		local now = DataService.now()
		GrowthService.settle(data, now)
		data.wateredUntil = math.min(data.wateredUntil, now)
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
	Net.on("Water", onWater)
	Net.on("BuyPotion", onBuyPotion)
	Net.on("SkipTimers", onSkipTimers)
	Net.on("BuyUpgrade", onBuyUpgrade)

	while true do
		task.wait(GameConfig.growthTickSeconds)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data and next(data.slots) then
				-- Clients compute growth from the last attributes; only resend when something mutated.
				local events = GrowthService.settle(data, DataService.now())
				if #events > 0 then
					announce(player, data, events)
					DataService.changed(player)
				end
				if data.ownedPasses.AutoHarvest then
					autoHarvest(player, data)
				end
			end
		end
	end
end

return GrowthService
