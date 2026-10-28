--!strict
-- The only writer of Cash and Gems. Every source and sink goes through addCash/spendCash
-- so it is sanity-checked and logged to Analytics. Also handles the Cash-priced intents:
-- buying eggs at the Egg Shop and selling mutants at the Sell Pad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Eggs = require(Shared.Config.Eggs)
local Valuation = require(Shared.Valuation)
local ShopRules = require(Shared.ShopRules)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local GroupRewardService = require(script.Parent.GroupRewardService)
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
	local lockedBefore = ShopRules.nextLocked(data.rebirths, data.stats.totalCashEarned)
	data.cash += amount
	data.stats.totalCashEarned += amount
	-- An earnings-gated tier (Lab) unlocking right now.
	if lockedBefore and ShopRules.isUnlocked(lockedBefore, data.rebirths, data.stats.totalCashEarned) then
		Net.notify(player, "🥚 " .. Eggs.tiers[lockedBefore].name .. " unlocked at the Egg Shop!", "success")
	end
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

-- Gems come only from Robux purchases and rewards, so there is no tier cap; just sanity.
local MAX_GEMS_PER_GRANT = 100_000

function EconomyService.addGems(
	player: Player,
	data: Types.Profile,
	amount: number,
	transactionType: string,
	sku: string?
): boolean
	if not isFinitePositive(amount) or amount > MAX_GEMS_PER_GRANT then
		return false
	end
	amount = math.floor(amount)
	data.gems += amount
	Analytics.economy(player, "Source", "Gems", amount, data.gems, transactionType, sku)
	DataService.changed(player)
	return true
end

function EconomyService.spendGems(
	player: Player,
	data: Types.Profile,
	amount: number,
	transactionType: string,
	sku: string?
): boolean
	if not isFinitePositive(amount) or data.gems < amount then
		return false
	end
	data.gems -= amount
	Analytics.economy(player, "Sink", "Gems", amount, data.gems, transactionType, sku)
	DataService.changed(player)
	return true
end

-- Rebirth: takes all Cash and leaves the starting amount. Logged as one sink and one source.
function EconomyService.resetCash(player: Player, data: Types.Profile, startingCash: number)
	if data.cash > 0 then
		Analytics.economy(player, "Sink", "Cash", data.cash, 0, "Gameplay", "Rebirth")
	end
	data.cash = startingCash
	Analytics.economy(player, "Source", "Cash", startingCash, data.cash, "Gameplay", "RebirthStart")
	DataService.changed(player)
end

local function itemValue(data: Types.Profile, item: Types.Item): number
	return Valuation.sellValue(item, DataService.cashMultiplier(data))
end

-- Sells one bag item at full value (Cash through addCash, so it's logged and counted in
-- totalCashEarned). Returns the value, or nil if there's no such item or the sale was refused.
function EconomyService.sellItem(player: Player, data: Types.Profile, itemId: string): number?
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
	-- One rule set with the shop UI: unlocks, Cash vs Gems, and the paid-random-item policy
	-- (Gem eggs are refused when PolicyService restricts them or the check hasn't succeeded).
	local ok, reason = ShopRules.canBuy(eggId, quantity, {
		rebirths = data.rebirths,
		totalCashEarned = data.stats.totalCashEarned,
		cash = data.cash,
		gems = data.gems,
		paidRandomRestricted = DataService.paidRandomRestricted[player] ~= false,
	})
	if not ok then
		if reason == "funds" then
			Net.notify(player, "Not enough " .. (ShopRules.price(eggId, quantity)), "info")
		elseif reason == "restricted" then
			Net.notify(player, "Gem eggs aren't available in your region", "info")
		end
		return
	end
	local currency, amount = ShopRules.price(eggId, quantity)
	if currency == "Gems" then
		if not EconomyService.spendGems(player, data, amount, "Shop", "GemEgg_" .. Eggs.baseOf(eggId)) then
			return
		end
		Analytics.funnel(player, data, "FirstGemEgg")
	elseif not EconomyService.spendCash(player, data, amount, "Shop", "Egg_" .. eggId) then
		return
	end
	data.eggs[eggId] = (data.eggs[eggId] or 0) + quantity
	data.stats.eggsBought += quantity
	Net.notify(player, string.format("Bought %d %s", quantity, tier.name), "success")
	DataService.changed(player)
end

local function onSell(player: Player, data: Types.Profile, itemId: any)
	if not Validate.string(itemId, 16) or not data.inventory[itemId] then
		return
	end
	GroupRewardService.beforeSale(player, data)
	local value = EconomyService.sellItem(player, data, itemId)
	if value then
		Analytics.funnel(player, data, "FirstSell")
		Net.notify(player, "Sold for " .. Format.cash(value), "success")
		GroupRewardService.afterSale(player, data)
	end
end

-- Sells the whole bag except pinned mutants.
local function onSellAll(player: Player, data: Types.Profile)
	GroupRewardService.beforeSale(player, data)
	local total, count = 0, 0
	for itemId, item in table.clone(data.inventory) do
		local value = if item.pinned then nil else EconomyService.sellItem(player, data, itemId)
		if value then
			total += value
			count += 1
		end
	end
	if count > 0 then
		Analytics.funnel(player, data, "FirstSell")
		Net.notify(player, string.format("Sold %d for %s", count, Format.cash(total)), "success")
		GroupRewardService.afterSale(player, data)
	end
end

local function onBuySlot(player: Player, data: Types.Profile)
	local cost = DataService.nextSlotCost(data)
	if not cost then
		return
	end
	if not EconomyService.spendCash(player, data, cost, "Shop", "Slot_" .. (data.slotCount + 1)) then
		return -- the client shows the earn-it / +10 slots offer instead of an error
	end
	data.slotCount += 1
	data.stats.slotsBought += 1
	Net.notify(player, "New soil patch unlocked!", "success")
	DataService.changed(player)
end

function EconomyService.Init() end

function EconomyService.Start()
	Net.on("BuyEgg", onBuyEgg)
	Net.on("Sell", onSell)
	Net.on("SellAll", onSellAll)
	Net.on("BuySlot", onBuySlot)
end

return EconomyService
