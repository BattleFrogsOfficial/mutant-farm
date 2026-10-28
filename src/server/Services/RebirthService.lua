--!strict
-- Rebirth: pay Costs.rebirth(n) Cash to start over with a permanent +0.5x Cash multiplier and the
-- next egg tier. Resets Cash (to startingCash), bought slots, upgrades, eggs (back to the starter
-- eggs) and growing plants; the bag is sold off except the mutants standing in the pen.
-- Keeps the pen, passes, Gems, the Almanac and the daily streak.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.Game)
local Upgrades = require(Shared.Config.Upgrades)
local Eggs = require(Shared.Config.Eggs)
local Costs = require(Shared.Costs)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local Net = require(script.Parent.Parent.Util.Net)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local RebirthService = {}

local function onRebirth(player: Player, data: Types.Profile)
	local cost = Costs.rebirth(data.rebirths)
	if data.cash < cost then
		return
	end
	-- The pen's mutants stay; the rest of the bag goes.
	local keep = {}
	for _, item in DataService.penItems(data) do
		keep[item.id] = item
	end
	data.inventory = keep
	EconomyService.resetCash(player, data, GameConfig.startingCash)
	data.rebirths += 1
	data.slotCount = Upgrades.slots.base
	data.slots = {}
	data.upgrades = { growthSpeed = 0, mutationOdds = 0 }
	data.eggs = table.clone(GameConfig.startingEggs)
	data.wateredUntil = 0
	Analytics.funnel(player, data, "FirstRebirth")

	local unlocked = nil
	for _, eggId in Eggs.order do
		if Eggs.tiers[eggId].unlockRebirth == data.rebirths then
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

function RebirthService.Init() end

function RebirthService.Start()
	Net.on("Rebirth", onRebirth)
end

return RebirthService
