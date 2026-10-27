--!strict
-- The only writer of Cash and Gems. Every source and sink goes through addCash/spendCash
-- so it is sanity-checked and logged to Analytics. Also handles the Cash-priced intents:
-- buying eggs at the Egg Shop and selling mutants at the Sell Pad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Valuation = require(Shared.Valuation)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Parent.Util.Net)
local Validate = require(script.Parent.Parent.Util.Validate)
local Analytics = require(script.Parent.Parent.Util.Analytics)

local EconomyService = {}

local MAX_EGGS_PER_PURCHASE = 100

local function isFinitePositive(n: number): boolean
	return n == n and n > 0 and n < math.huge
end

-- Adds Cash. Rejects (and warns) amounts above the theoretical max for the player's tier.
function EconomyService.addCash(
	player: Player,
	data: Types.Profile,
	amount: number,
	transactionType: string,
	sku: string?
): boolean
	if not isFinitePositive(amount) then
		return false
	end
	local cap = Valuation.maxSingleSale(data.rebirths, DataService.cashMultiplier(data))
	if amount > cap then
		warn(
			string.format("[Economy] rejected %s Cash for %s (cap %s, sku %s)", amount, player.Name, cap, tostring(sku))
		)
		return false
	end
	amount = math.floor(amount)
	data.cash += amount
	data.stats.cashEarned += amount
	Analytics.economy(player, "Source", "Cash", amount, data.cash, transactionType, sku)
	DataService.changed(player)
	return true
end

function EconomyService.spendCash(
	player: Player,
	data: Types.Profile,
	amount: number,
	transactionType: string,
	sku: string?
): boolean
	if not isFinitePositive(amount) or data.cash < amount then
		return false
	end
	data.cash -= amount
	Analytics.economy(player, "Sink", "Cash", amount, data.cash, transactionType, sku)
	DataService.changed(player)
	return true
end

local function itemValue(data: Types.Profile, item: Types.Item): number
	return Valuation.sellValue(item, DataService.cashMultiplier(data))
end

local function sellItem(player: Player, data: Types.Profile, itemId: string): number?
	local item = data.inventory[itemId]
	if not item then
		return nil
	end
	local value = itemValue(data, item)
	if not EconomyService.addCash(player, data, value, "Gameplay", "Sell_" .. item.tier .. "_" .. item.rarity) then
		return nil
	end
	data.inventory[itemId] = nil
	data.stats.sold += 1
	return value
end

local function onBuyEgg(player: Player, data: Types.Profile, eggId: any, quantity: any)
	if not Validate.string(eggId, 32) or not Validate.integer(quantity, 1, MAX_EGGS_PER_PURCHASE) then
		return
	end
	local tier = Eggs.tiers[eggId]
	if not tier or tier.unlockRebirth > data.rebirths then
		return
	end
	local cost = tier.cost * quantity
	if not EconomyService.spendCash(player, data, cost, "Shop", "Egg_" .. eggId) then
		Net.notify(player, "Not enough Cash", "error")
		return
	end
	data.eggs[eggId] = (data.eggs[eggId] or 0) + quantity
	data.stats.eggsBought += quantity
	Net.notify(player, string.format("Bought %d %s", quantity, tier.name), "success")
	DataService.changed(player)
end

local function onSell(player: Player, data: Types.Profile, itemId: any)
	if not Validate.string(itemId, 16) then
		return
	end
	local value = sellItem(player, data, itemId)
	if value then
		Analytics.funnel(player, data, "FirstSell")
		Net.notify(player, "Sold for " .. Format.cash(value), "success")
	end
end

local function onSellAll(player: Player, data: Types.Profile)
	local total, count = 0, 0
	for itemId in table.clone(data.inventory) do
		local value = sellItem(player, data, itemId)
		if value then
			total += value
			count += 1
		end
	end
	if count > 0 then
		Analytics.funnel(player, data, "FirstSell")
		Net.notify(player, string.format("Sold %d for %s", count, Format.cash(total)), "success")
	end
end

function EconomyService.Init() end

function EconomyService.Start()
	Net.on("BuyEgg", onBuyEgg)
	Net.on("Sell", onSell)
	Net.on("SellAll", onSellAll)
end

return EconomyService
