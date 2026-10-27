--!strict
-- Planting, growing, watering and harvesting. No per-frame work: each slot stores growth as of
-- updatedAt, and `settle` advances every slot to "now" with shared/Growth.lua. That runs on
-- join (which is how offline growth happens), before any change, and on a slow tick.
--
-- M1: every hatch is Common with no mutations and size 1. M2 replaces `rollOnPlant`,
-- `rollOnHarvest` and the mutation hook in `settle` with shared/Rolls.lua.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local GameConfig = require(Shared.Config.Game)
local Growth = require(Shared.Growth)
local Valuation = require(Shared.Valuation)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local GrowthService = {}

local function rollOnPlant(_data: Types.Profile, _eggId: string): string
	return "Common"
end

local function rollOnHarvest(_data: Types.Profile, _slot: Types.Slot): number
	return 1
end

-- Advances every slot on the plot to `now`.
function GrowthService.settle(data: Types.Profile, now: number)
	local speed = DataService.speed(data)
	for _, slot in data.slots do
		if now > slot.updatedAt then
			local required = Growth.requiredSeconds(slot.eggId, slot.rarity)
			local grown = Growth.advance(slot.growth, slot.updatedAt, now, data.wateredUntil, speed)
			-- M2: apply Growth.rollsCrossed(slot.growth, grown, required) mutation rolls here,
			-- skipping rolls more than offlineMutationCap after data.lastSeen while offline.
			slot.rollsDone += Growth.rollsCrossed(slot.growth, grown, required)
			slot.growth = math.min(grown, required)
			slot.updatedAt = now
		end
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

local function sync(player: Player, data: Types.Profile)
	PlotService.refresh(player, data)
	DataService.changed(player)
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
	GrowthService.settle(data, now)
	data.eggs[eggId] -= 1
	if data.eggs[eggId] <= 0 then
		data.eggs[eggId] = nil
	end
	data.slots[key] = {
		eggId = eggId,
		rarity = rollOnPlant(data, eggId),
		mutations = {},
		size = 1,
		plantedAt = now,
		growth = 0,
		updatedAt = now,
		rollsDone = 0,
		lastRollAt = now,
	}
	data.stats.eggsPlanted += 1
	Analytics.funnel(player, data, "FirstPlant")
	sync(player, data)
end

-- Returns the harvested item, or nil (and a reason) if the slot can't be harvested.
local function harvest(player: Player, data: Types.Profile, key: string): (Types.Item?, string?)
	local slot = data.slots[key]
	if not slot or not isMature(slot) then
		return nil, nil
	end
	if inventoryCount(data) >= GameConfig.inventoryCap then
		return nil, "Inventory full! Sell at the Sell Pad."
	end
	local id = tostring(data.nextItemId)
	data.nextItemId += 1
	local item: Types.Item = {
		id = id,
		tier = slot.eggId,
		rarity = slot.rarity,
		mutations = slot.mutations,
		size = rollOnHarvest(data, slot),
		harvestedAt = DataService.now(),
	}
	data.inventory[id] = item
	data.slots[key] = nil
	data.stats.harvested += 1
	Analytics.funnel(player, data, "FirstHarvest")
	Net.fire(player, "Harvested", item, Valuation.sellValue(item, DataService.cashMultiplier(data)))
	return item, nil
end

local function onHarvest(player: Player, data: Types.Profile, slotIndex: any)
	if not Validate.integer(slotIndex, 1, data.slotCount) then
		return
	end
	GrowthService.settle(data, DataService.now())
	local _, reason = harvest(player, data, tostring(slotIndex))
	if reason then
		Net.notify(player, reason, "error")
	end
	sync(player, data)
end

local function onHarvestAll(player: Player, data: Types.Profile)
	GrowthService.settle(data, DataService.now())
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
		Net.notify(player, string.format("Harvested %d mutants worth %s", count, Format.cash(value)), "success")
	end
	if reason then
		Net.notify(player, reason, "error")
	end
	sync(player, data)
end

local function onWater(player: Player, data: Types.Profile)
	local now = DataService.now()
	if now < data.wateredUntil then
		return
	end
	-- Settle at the old speed before the watering window starts.
	GrowthService.settle(data, now)
	data.wateredUntil = now + GameConfig.waterDuration
	sync(player, data)
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
		-- Offline growth: everything since the last save is a pure function of timestamps.
		GrowthService.settle(data, DataService.now())
		Analytics.funnel(player, data, "Joined")
		sync(player, data)
	end)

	Net.on("Plant", onPlant)
	Net.on("Harvest", onHarvest)
	Net.on("HarvestAll", onHarvestAll)
	Net.on("Water", onWater)

	-- Slow tick keeps saved growth fresh (and runs mutation rolls from M2 on).
	while true do
		task.wait(GameConfig.growthTickSeconds)
		local now = DataService.now()
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if data then
				GrowthService.settle(data, now)
				sync(player, data)
			end
		end
	end
end

return GrowthService
