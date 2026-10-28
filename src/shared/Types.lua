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
	streak: { day: number, lastClaimDay: number },
	redeemedCodes: { [string]: boolean },
	funnel: { [string]: boolean },
	grantedStarterEggs: boolean,
	almanac: { [string]: AlmanacEntry },
	stats: {
		eggsBought: number,
		eggsPlanted: number,
		harvested: number,
		sold: number,
		cashEarned: number,
		waters: number,
		slotsBought: number,
	},
	nextItemId: number,
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
}

return {}
