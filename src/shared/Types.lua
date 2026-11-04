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
	weatherRolled: { [string]: boolean }?, -- weather events that gave this egg its one roll (WeatherRules.key)
	baseGrow: number?, -- onboarding grow ramp: seconds as a Common instead of the tier's
	scripted: string?, -- "firstHatch": the scripted first hatch (no rolls; fixed outcome)
	firstRare: boolean?, -- the guaranteed Rare (the 2nd egg): its reveal offers the Starter Bundle
}

-- An owned patch's Auto-Harvest settings (kept while the patch is empty, unlike its Slot).
export type Patch = {
	replant: boolean, -- after a harvest, plant the same egg again (Auto-Harvest pass)
	egg: string?, -- the last egg planted here: what gets replanted
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
	valueScale: number?, -- multiplies its value after everything else (the scripted first hatch)
	scripted: string?, -- "firstHatch": a scripted outcome (no odds, analytics or Top Pens)
}

export type AlmanacEntry = { n: number, first: number, best: number, firstHatch: boolean? }

export type Profile = {
	version: number,
	cash: number,
	gems: number,
	rebirths: number,
	slotCount: number,
	slots: { [string]: Slot }, -- keyed by tostring(slotIndex); missing = empty
	patches: { [string]: Patch }, -- keyed by tostring(slotIndex); missing = replant off, no egg yet
	eggs: { [string]: number },
	inventory: { [string]: Item }, -- keyed by item id
	pen: { [string]: Item },
	upgrades: { growthSpeed: number, mutationOdds: number },
	gemUpgrades: { penSlots: number, luck: number, offline: number }, -- Gem upgrades, kept through rebirth
	ownedPasses: { [string]: boolean },
	processedPurchases: { [string]: number },
	wateredUntil: number, -- the tap boost runs until then...
	waterMult: number, -- ...at this multiplier
	waterOffer: number, -- the next tap's multiplier (0 = not rolled yet)
	onPad: boolean, -- standing on the plot's water pad right now (false on join and offline)
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
		waters: number, -- growth circle taps
		padVisits: number, -- times stepped onto the water pad
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
	onboarding: {
		active: boolean, -- created with the scripted opening (Config/Onboarding)
		preplanted: boolean, -- its first egg was planted for it
		firstHatch: boolean, -- the scripted first hatch happened
		shopOpened: boolean, -- the Egg Shop was opened once (the tray's BUY button goes)
		weather: boolean, -- the free solo Solar Flare happened
		bundle: boolean, -- the Starter Bundle window started (on the first Rare's reveal)
		playSeconds: number, -- online seconds so far (the solo weather waits for 2:30)
	},
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
	waterMult: number,
	waterOffer: number,
	onPad: boolean,
	eggs: { [string]: number },
	slots: { [string]: SlotView },
	replant: { [string]: boolean }, -- patches with the Auto-Harvest replant toggle on
	inventory: { [string]: Item },
	inventoryCap: number,
	nextSlotCost: number?,
	stats: { [string]: number },
	incomePerMinute: number, -- the pen's income, $/min (cents kept); eggs earn nothing until hatched
	growingCount: number, -- planted eggs still growing
	readyCount: number, -- planted eggs mature, waiting to be hatched
	penPerMinute: number, -- the pen's part (what the payouts pay)
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
	gemUpgrades: { penSlots: number, luck: number, offline: number },
	penCapacity: number, -- mutants the pen holds (and the pin cap)
	almanacRewards: number,
	inGroup: boolean,
	almanacLuck: number,
	vipGemsReady: boolean, -- VIP pass: today's Gems can be claimed
	seenLimited: { [string]: boolean },
	onboarding: { active: boolean, shopOpened: boolean, weather: boolean }?,
}

return {}
