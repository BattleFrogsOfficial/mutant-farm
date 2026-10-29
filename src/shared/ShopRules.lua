--!strict
-- Who can buy which egg, for what. The server's buy handler and the shop UI both use this, so the
-- rules (unlocks, Cash vs Gems prices, the paid-random-item policy) live in one place.

local Eggs = require(script.Parent.Config.Eggs)
local Products = require(script.Parent.Config.Products)

local ShopRules = {}

export type Buyer = {
	rebirths: number,
	totalCashEarned: number,
	cash: number,
	gems: number,
	-- PolicyService: true (or unknown) = paid random items are restricted for this player.
	paidRandomRestricted: boolean,
	-- Server time, for limited eggs' sale windows (omitted = limited eggs aren't on sale).
	now: number?,
}

-- Is this egg tier (or its Gem variant) unlocked?
function ShopRules.isUnlocked(eggId: string, rebirths: number, totalCashEarned: number): boolean
	local tier = Eggs.tiers[eggId]
	if not tier then
		return false
	end
	if rebirths < tier.unlockRebirth then
		return false
	end
	-- Earned gates only apply at the unlock rebirth itself (Lab at Rebirth 0).
	if tier.unlockEarned and rebirths == tier.unlockRebirth and totalCashEarned < tier.unlockEarned then
		return false
	end
	return true
end

-- Is a limited egg on sale at server time `now`? (window inclusive: startsAt <= now <= endsAt)
function ShopRules.isLimitedActive(eggId: string, now: number): boolean
	local tier = Eggs.tiers[eggId]
	return tier ~= nil and tier.limited == true and now >= tier.startsAt and now <= tier.endsAt
end

-- The limited eggs on sale at `now`, in config order.
function ShopRules.activeLimited(now: number): { string }
	local out = {}
	for _, id in Eggs.limitedOrder do
		if ShopRules.isLimitedActive(id, now) then
			table.insert(out, id)
		end
	end
	return out
end

-- The limited eggs a buyer sees in the shop: on sale, and not policy-restricted.
function ShopRules.shownLimited(now: number, paidRandomRestricted: boolean): { string }
	return if paidRandomRestricted then {} else ShopRules.activeLimited(now)
end

-- Gem variants and limited eggs are paid random items (bought with Robux-bought Gems).
function ShopRules.isGemEgg(eggId: string): boolean
	local tier = Eggs.tiers[eggId]
	return tier ~= nil and tier.gemCost ~= nil
end

-- What `quantity` of this egg costs: currency ("Cash" | "Gems") and amount.
function ShopRules.price(eggId: string, quantity: number): (string, number)
	local tier = Eggs.tiers[eggId]
	if tier.gemCost then
		return "Gems", tier.gemCost * quantity
	end
	return "Cash", tier.cost * quantity
end

-- Can this buyer buy `quantity` of `eggId`? Returns ok, and a reason when not:
-- "unknown" | "locked" | "restricted" | "ended" | "funds".
function ShopRules.canBuy(eggId: string, quantity: number, buyer: Buyer): (boolean, string?)
	if not Eggs.tiers[eggId] then
		return false, "unknown"
	end
	if ShopRules.isGemEgg(eggId) and buyer.paidRandomRestricted then
		return false, "restricted"
	end
	if not ShopRules.isUnlocked(eggId, buyer.rebirths, buyer.totalCashEarned) then
		return false, "locked"
	end
	if Eggs.tiers[eggId].limited and not (buyer.now and ShopRules.isLimitedActive(eggId, buyer.now)) then
		return false, "ended"
	end
	local currency, amount = ShopRules.price(eggId, quantity)
	local have = if currency == "Gems" then buyer.gems else buyer.cash
	if have < amount then
		return false, "funds"
	end
	return true, nil
end

-- The Luck Potion is a paid odds boost: refused where paid random items are restricted (or unknown).
function ShopRules.canBuyPotion(paidRandomRestricted: boolean): boolean
	return not paidRandomRestricted
end

-- Rebirth Now is offered (Rebirth panel, Rebirth Altar sign) while Cash is from minFraction (50%)
-- of the next rebirth's cost up to just under it. The server accepts it from minFraction up.
function ShopRules.rebirthNowOffered(cash: number, cost: number): boolean
	return cost > 0 and cash >= cost * Products.gems.RebirthNow.minFraction and cash < cost
end

-- Instant Weather is a paid mutation-odds boost too: gated exactly like the Luck Potion.
function ShopRules.canBuyInstantWeather(paidRandomRestricted: boolean): boolean
	return ShopRules.canBuyPotion(paidRandomRestricted)
end

-- Base tiers unlocked now that weren't before (e.g. Lab when lifetime earnings cross $25K).
function ShopRules.newlyUnlocked(
	before: { rebirths: number, totalCashEarned: number },
	after: { rebirths: number, totalCashEarned: number }
): { string }
	local out = {}
	for _, id in Eggs.order do
		if
			ShopRules.isUnlocked(id, after.rebirths, after.totalCashEarned)
			and not ShopRules.isUnlocked(id, before.rebirths, before.totalCashEarned)
		then
			table.insert(out, id)
		end
	end
	return out
end

-- The next tier the player hasn't unlocked yet (base tiers only), or nil.
function ShopRules.nextLocked(rebirths: number, totalCashEarned: number): string?
	for _, id in Eggs.order do
		if not ShopRules.isUnlocked(id, rebirths, totalCashEarned) then
			return id
		end
	end
	return nil
end

-- The egg tray's one "next egg" tile: the cheapest base tier (Cash-priced, Eggs.order) the player
-- has none of (count 0 or missing) that is already unlocked, or nil. Earned- and rebirth-gated
-- tiers never qualify (their progress lives in the Egg Shop carousel and Next Up).
function ShopRules.nextTrayEgg(eggs: { [string]: number }, rebirths: number, totalCashEarned: number): string?
	local best: string? = nil
	for _, id in Eggs.order do
		local tier = Eggs.tiers[id]
		if (eggs[id] or 0) <= 0 and not tier.gemCost and ShopRules.isUnlocked(id, rebirths, totalCashEarned) then
			if best == nil or tier.cost < Eggs.tiers[best].cost then
				best = id
			end
		end
	end
	return best
end

-- The base tier that rebirth number `n` unlocks (Toxic at 1, Void at 3, ...), or nil.
function ShopRules.unlockedAtRebirth(n: number): string?
	for _, id in Eggs.order do
		local tier = Eggs.tiers[id]
		if tier.unlockRebirth == n and not tier.gemCost then
			return id
		end
	end
	return nil
end

return ShopRules
