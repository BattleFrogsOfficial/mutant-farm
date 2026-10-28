--!strict
-- Shared data shapes. Profile data must stay JSON-safe: no arrays with holes,
-- no mixed keys, no Instances or userdata.

export type Slot = {
	eggId: string,
	rarity: string, -- rolled at planting, revealed at harvest
	species: string?, -- Mutants.species id, rolled with rarity
	mutations: { string },
	size: number, -- rolled at harvest; 1 while growing
	plantedAt: number,
	growth: number, -- effective seconds grown as of updatedAt
	updatedAt: number,
	rollsDone: number,
	lastRollAt: number,
}

export type Item = {
	id: string,
	tier: string,
	rarity: string,
	species: string?,
	mutations: { string },
	size: number,
	harvestedAt: number,
	egg: string?, -- the egg it hatched from (a Gem variant's id; tier is always the base tier)
	pinned: boolean?, -- always stands in the pen; skipped by Sell All and kept on rebirth
}

export type AlmanacEntry = { n: number, first: number, best: number }

export type Profile = {
	version: number,
	cash: number,
	gems: number,
	rebirths: number,
	slotCount: number,
	slots: { [string]: Slot }, -- keyed by tostring(slotIndex); missing = empty
	eggs: { [string]: number },
	inventory: { [string]: Item }, -- keyed by item id
	pen: { [string]: Item },
	upgrades: { growthSpeed: number, mutationOdds: number },
	ownedPasses: { [string]: boolean },
	processedPurchases: { [string]: number },
	wateredUntil: number,
	lastSeen: number,
	streak: { day: number, lastClaimDay: number, count: number },
	redeemedCodes: { [string]: boolean },
	funnel: { [string]: boolean },
	grantedStarterEggs: boolean,
	almanac: { [string]: AlmanacEntry },
	stats: {
		eggsBought: number,
		eggsPlanted: number,
		harvested: number,
		sold: number,
		totalCashEarned: number, -- lifetime Cash earned (every source); never reduced by spending
		waters: number,
		slotsBought: number,
	},
	nextItemId: number,
	bundleOfferEndsAt: number, -- Starter Bundle offer window (set on first join)
	bundleBought: boolean,
	fastHatch: boolean, -- player setting: short hatch cutscene below Epic
	potionUntil: number, -- Luck Potion active until this server time
	groupRewardClaimed: boolean,
	almanacRewards: number, -- Almanac milestones already paid
	inGroup: boolean, -- group member as of the last check (join / Claim): +10% Cash
	almanacLuck: number, -- permanent luck bonus from Almanac milestones (0.1 = +10%)
	groupOffered: boolean, -- the group offer was shown (once, at the first sale)
	vipGemsDay: number, -- UTC day of the last VIP daily Gems claim
	seenLimited: { [string]: boolean }, -- limited egg id -> the shop has opened on it once
}

export type SlotView = {
	index: number,
	eggId: string,
	growth: number,
	updatedAt: number,
	required: number,
}

export type Snapshot = {
	serverTime: number,
	cash: number,
	gems: number,
	rebirths: number,
	slotCount: number,
	cashMultiplier: number,
	speed: number,
	wateredUntil: number,
	eggs: { [string]: number },
	slots: { [string]: SlotView },
	inventory: { [string]: Item },
	inventoryCap: number,
	nextSlotCost: number?,
	stats: { [string]: number },
	incomePerMinute: number,
	nextPayoutAt: number,
	payoutSeconds: number,
	daily: { day: number, canClaim: boolean, streak: number },
	totalSlots: number, -- bought slots + pass slots (slotCount is bought only)
	ownedPasses: { [string]: boolean },
	rebirthCost: number,
	bundleOfferEndsAt: number, -- 0 when not on offer
	fastHatch: boolean,
	potionUntil: number,
	groupRewardClaimed: boolean,
	paidRandomRestricted: boolean, -- PolicyService: no paid odds boosts (Luck Potion) for this player
	upgrades: { growthSpeed: number, mutationOdds: number },
	upgradeCosts: { growthSpeed: number?, mutationOdds: number? }, -- nil = maxed
	almanacRewards: number,
	inGroup: boolean,
	almanacLuck: number,
	vipGemsReady: boolean, -- VIP pass: today's Gems can be claimed
	seenLimited: { [string]: boolean },
}

return {}
