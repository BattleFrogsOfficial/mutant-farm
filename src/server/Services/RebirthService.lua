--!strict
-- Rebirth: pay Costs.rebirth(n) Cash to start over with a permanent +0.5x Cash multiplier and the
-- next egg tier. First the bag is sold at full value through EconomyService (logged, and counted
-- in stats.totalCashEarned), except the mutants standing in the pen (pinned ones always are).
-- Then it resets Cash (to startingCash, so the sale's Cash goes with the rest), bought slots,
-- upgrades, eggs (back to the starter eggs) and growing plants. Keeps the pen, passes, Gems, the
-- Almanac and the daily streak. Rebirth Now (Products.gems.RebirthNow) does the same from 50% of
-- the cost, for Gems.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Upgrades = require(Shared.Config.Upgrades)
local Eggs = require(Shared.Config.Eggs)
local Costs = require(Shared.Costs)
local Products = require(Shared.Config.Products)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local RebirthService = {}

-- The rebirth itself (both ways in: Cash, or Rebirth Now for Gems).
local function rebirth(player: Player, data: Types.Profile)
	-- The pen's mutants stay; the rest of the bag is sold before the reset.
	local keep = {}
	for _, item in DataService.penItems(data) do
		keep[item.id] = item
	end
	for itemId in table.clone(data.inventory) do
		if not keep[itemId] then
			EconomyService.sellItem(player, data, itemId)
		end
	end
	data.inventory = keep
	EconomyService.resetCash(player, data, GameConfig.startingCash)
	data.rebirths += 1
	data.slotCount = Upgrades.slots.base
	-- Gem eggs were bought with Gems: they survive the reset, including ones still growing.
	local keptEggs = table.clone(GameConfig.startingEggs)
	for eggId, count in data.eggs do
		if Eggs.tiers[eggId] and Eggs.tiers[eggId].gemCost then
			keptEggs[eggId] = (keptEggs[eggId] or 0) + count
		end
	end
	for _, slot in data.slots do
		if Eggs.tiers[slot.eggId] and Eggs.tiers[slot.eggId].gemCost then
			keptEggs[slot.eggId] = (keptEggs[slot.eggId] or 0) + 1
		end
	end
	data.slots = {}
	data.upgrades = { growthSpeed = 0, mutationOdds = 0 }
	data.eggs = keptEggs
	data.wateredUntil = 0
	Analytics.funnel(player, data, "FirstRebirth")

	local unlocked = nil
	for _, eggId in Eggs.order do
		if Eggs.tiers[eggId].unlockRebirth == data.rebirths and not Eggs.tiers[eggId].unlockEarned then
			unlocked = Eggs.tiers[eggId].name
		end
	end
	Net.fire(player, "Rebirthed", data.rebirths)
	Net.notify(
		player,
		string.format("REBIRTH %d! Cash x%s forever", data.rebirths, tostring(DataService.cashMultiplier(data)))
			.. (if unlocked then " · " .. unlocked .. " unlocked!" else ""),
		"success"
	)
	DataService.changed(player)
end

local function onRebirth(player: Player, data: Types.Profile)
	if data.cash < Costs.rebirth(data.rebirths) then
		return
	end
	rebirth(player, data)
end

-- Rebirth Now: from minFraction (50%) of the cost, for Gems. The normal rebirth runs exactly (bag
-- sold first, the usual resets), then the Gems are taken (checked first, so it can't half-happen).
local function onRebirthNow(player: Player, data: Types.Profile)
	local offer = Products.gems.RebirthNow
	if data.cash < Costs.rebirth(data.rebirths) * offer.minFraction then
		return
	end
	if data.gems < offer.cost then
		Net.notify(player, string.format("Need %d Gems to Rebirth Now", offer.cost), "info")
		return
	end
	rebirth(player, data)
	EconomyService.spendGems(player, data, offer.cost, "Shop", "RebirthNow")
	DataService.changed(player)
end

function RebirthService.Init() end

function RebirthService.Start()
	Net.on("Rebirth", onRebirth)
	Net.on("RebirthNow", onRebirthNow)
end

return RebirthService
