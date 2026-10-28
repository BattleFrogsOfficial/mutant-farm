--!strict
-- Egg tiers. All balance numbers for eggs live here; logic never hardcodes them.
-- growTime is in seconds for a Common hatch; Rarities.growMultiplier stretches it.
-- odds are percentages (must sum to 100) and are what the in-game odds panel shows.
-- design: shell look (pattern: spots | blotches | hazard | cracks | stars | ring); color is the UI swatch.
-- Unlock: unlockRebirth rebirths, plus unlockEarned lifetime Cash earned if set (Lab: 3 eggs before
-- the first rebirth). shared/ShopRules.lua is the one place that checks it.
-- tagline: one line shown on the Egg Shop card while the tier is further locked.
--
-- Gem variants ("<Tier>Gem", generated at the bottom): same design with a gem overlay, same species,
-- grow time and values, bought with Gems. Their rarity table is the base tier's Uncommon-and-above
-- weights doubled, then renormalized to 100 (a separate base table, not luck: the 2x Luck pass and
-- the Luck Potion still apply on top, and the 6x luck cap is unaffected). Paid random items: hidden
-- and refused where PolicyService restricts them.

local Eggs = {}

Eggs.order = { "Starter", "Swamp", "Lab", "Toxic", "Void", "Cosmic" }

Eggs.tiers = {
	Starter = {
		id = "Starter",
		design = { pattern = "spots", shell = "#F6F0D8", accent = "#9BE04A" },
		name = "Starter Egg",
		tagline = "Everybody starts somewhere",
		unlockRebirth = 0,
		cost = 50,
		growTime = 60,
		baseValue = 80,
		color = "#C9F27A",
		odds = { Common = 80, Uncommon = 15, Rare = 4.45, Epic = 0.5, Legendary = 0.05 },
	},
	Swamp = {
		id = "Swamp",
		design = { pattern = "blotches", shell = "#7FA85A", accent = "#3E5E2A" },
		name = "Swamp Egg",
		tagline = "Smells like adventure",
		unlockRebirth = 0,
		cost = 500,
		growTime = 5 * 60,
		baseValue = 900,
		color = "#5E9C4A",
		odds = { Common = 75, Uncommon = 18, Rare = 6, Epic = 0.93, Legendary = 0.07 },
	},
	Lab = {
		id = "Lab",
		design = { pattern = "hazard", shell = "#EEF3F8", accent = "#4AB8FF" },
		name = "Lab Egg",
		tagline = "Where things go wrong",
		unlockRebirth = 0,
		unlockEarned = 25_000, -- also needs this much lifetime Cash earned (stats.totalCashEarned)
		-- 45K (was 5K) since Lab moved to Rebirth 0: at 5K it snowballed the first rebirth down to
		-- ~19 min. tools/sim plateaus at ~31 min here; higher prices make the bot fall back to Swamp.
		cost = 45_000,
		growTime = 20 * 60,
		baseValue = 11_000,
		color = "#E8EEF5",
		odds = { Common = 70, Uncommon = 20, Rare = 8, Epic = 1.9, Legendary = 0.1 },
	},
	Toxic = {
		id = "Toxic",
		design = { pattern = "cracks", shell = "#3B4A2A", accent = "#7CFF4A", glow = true },
		name = "Toxic Egg",
		tagline = "Handle with gloves",
		unlockRebirth = 1,
		cost = 50_000,
		growTime = 60 * 60,
		baseValue = 130_000,
		color = "#7CFF4A",
		odds = { Common = 65, Uncommon = 22, Rare = 10, Epic = 2.875, Legendary = 0.125 },
	},
	Void = {
		id = "Void",
		design = { pattern = "stars", shell = "#2B2140", accent = "#C29BFF", glow = true },
		name = "Void Egg",
		tagline = "Stares back",
		unlockRebirth = 3,
		cost = 500_000,
		growTime = 3 * 60 * 60,
		baseValue = 1_600_000,
		color = "#2B2140",
		odds = { Common = 60, Uncommon = 24, Rare = 12, Epic = 3.8, Legendary = 0.2 },
	},
	Cosmic = {
		id = "Cosmic",
		design = { pattern = "ring", shell = "#5A2DFF", accent = "#FFD24A", glow = true },
		name = "Cosmic Egg",
		tagline = "From beyond the stars",
		unlockRebirth = 6,
		cost = 5_000_000,
		growTime = 8 * 60 * 60,
		baseValue = 20_000_000,
		color = "#9B5CFF",
		odds = { Common = 55, Uncommon = 25, Rare = 14, Epic = 5.67, Legendary = 0.33 },
	},
}

-- Gem variant prices (Gems per egg; the x5 pack is 5x).
Eggs.gemCosts = { Starter = 15, Swamp = 40, Lab = 120, Toxic = 300, Void = 800, Cosmic = 2_000 }
Eggs.gemOddsMultiplier = 2 -- Uncommon-and-above weights x this, then renormalized

Eggs.gemOrder = {}
for i, baseId in Eggs.order do
	local base = Eggs.tiers[baseId]
	local odds = {}
	local total = 0
	for rarity, weight in base.odds do
		local w = if rarity == "Common" then weight else weight * Eggs.gemOddsMultiplier
		odds[rarity] = w
		total += w
	end
	for rarity, w in odds do
		odds[rarity] = w / total * 100
	end
	local id = baseId .. "Gem"
	local design = table.clone(base.design)
	design.gem = true
	Eggs.tiers[id] = {
		id = id,
		base = baseId,
		gemCost = Eggs.gemCosts[baseId],
		design = design,
		name = base.name:gsub(" Egg$", "") .. " Gem Egg",
		tagline = base.tagline,
		unlockRebirth = base.unlockRebirth,
		unlockEarned = base.unlockEarned,
		cost = base.cost, -- Cash price of the base tier (not for sale for Cash)
		growTime = base.growTime,
		baseValue = base.baseValue,
		color = base.color,
		odds = odds,
	}
	Eggs.gemOrder[i] = id
end

-- The tier an egg belongs to (Gem variants -> their base tier): species, values and the Almanac.
function Eggs.baseOf(eggId: string): string
	local tier = Eggs.tiers[eggId]
	return if tier and tier.base then tier.base else eggId
end

return Eggs
