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
local Growth = require(Shared.Growth)
local Rolls = require(Shared.Rolls)
local Rng = require(Shared.Rng)
local Valuation = require(Shared.Valuation)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local GrowthService = {}

local rng = Rng.new(Random.new():NextInteger(1, 2 ^ 31 - 1))

local GUARANTEED_RARE_PLANT = 2 -- the Nth egg a player ever plants

local function luck(data: Types.Profile): number
	return if data.ownedPasses.Luck2x then 2 else 1
end

local function oddsBonus(data: Types.Profile): number
	return Upgrades.mutationOdds.bonusPerLevel * data.upgrades.mutationOdds
end

local function rollSpecies(eggId: string, rarity: string): string
	local bucket = Mutants.buckets[eggId][rarity]
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

local function announce(player: Player, events: { MutationEvent })
	for _, e in events do
		Net.fire(player, "Mutated", e.slotIndex, e.eggId, e.mutation)
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
	announce(player, GrowthService.settle(data, DataService.now()))
end

local function onPlant(player: Player, data: Types.Profile, slotIndex: any, eggId: any)
	if not Validate.integer(slotIndex, 1, data.slotCount) or not Validate.string(eggId, 32) then
		return
	end
	local key = tostring(slotIndex)
	if data.slots[key] or not Eggs.tiers[eggId] then
		return
	end
	if (data.eggs[eggId] or 0) < 1 then
		Net.notify(player, "You're out of that egg. Buy more at the Egg Shop!", "error")
		return
	end
	local now = DataService.now()
	settleNow(player, data)
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
end

-- Returns the harvested item, or nil (and a reason) if the slot can't be harvested.
local function harvest(player: Player, data: Types.Profile, key: string): (Types.Item?, string?)
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
		tier = slot.eggId,
		rarity = slot.rarity,
		species = slot.species or rollSpecies(slot.eggId, slot.rarity),
		mutations = slot.mutations,
		size = Rolls.rollSize(rng, luck(data)),
		harvestedAt = DataService.now(),
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
	Net.fire(player, "Almanac", { [speciesId] = entry })

	Net.fire(
		player,
		"Harvested",
		item,
		Valuation.sellValue(item, DataService.cashMultiplier(data)),
		tonumber(key),
		isNew
	)
	return item, nil
end

local function onHarvest(player: Player, data: Types.Profile, slotIndex: any)
	if not Validate.integer(slotIndex, 1, data.slotCount) then
		return
	end
	settleNow(player, data)
	local _, reason = harvest(player, data, tostring(slotIndex))
	if reason then
		Net.notify(player, reason, "error")
	end
	DataService.changed(player)
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

-- Offline catch-up: mutation rolls run for the first offlineMutationCap seconds away
-- (or the whole time with the Offline Mutations pass); growth always runs.
local function catchUp(player: Player, data: Types.Profile)
	local now = DataService.now()
	if data.lastSeen > 0 and not data.ownedPasses.OfflineMutations then
		local capAt = data.lastSeen + GameConfig.offlineMutationCap
		if now > capAt then
			GrowthService.settle(data, capAt)
			GrowthService.settle(data, now, false)
			if next(data.slots) then
				Net.notify(player, "Your eggs stopped mutating after 2 hours away.", "info")
			end
			return
		end
	end
	GrowthService.settle(data, now)
	local _ = player
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

	while true do
		task.wait(GameConfig.growthTickSeconds)
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data and next(data.slots) then
				-- Clients compute growth from the last attributes; only resend when something mutated.
				local events = GrowthService.settle(data, DataService.now())
				if #events > 0 then
					announce(player, events)
					DataService.changed(player)
				end
			end
		end
	end
end

return GrowthService
