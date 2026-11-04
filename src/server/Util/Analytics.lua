--!strict
-- Thin wrapper over AnalyticsService. Analytics must never break gameplay, so every call is pcall'd.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

-- First-session funnel. Steps must be logged in order and once per player.
Analytics.Funnel = {
	Joined = 1,
	FirstPlant = 2,
	FirstHatch = 3, -- (was FirstHarvest) carries seconds since join

	FirstSell = 4,
	FirstRebirth = 5, -- M4
	FirstPurchasePrompt = 6,
}

-- Steps outside the onboarding funnel (they can happen in any order relative to it), each logged
-- once per player as its own single-step funnel: name -> funnel name.
Analytics.OtherFunnels = {
	FirstGemEgg = "GemEggs",
	FirstLimitedEgg = "LimitedEggs",
}

-- Tests: called with (player, stepName, seconds?) for every funnel step logged (nil in the game).
Analytics.funnelObserver = nil :: ((Player, string, number?) -> ())?

-- `seconds` (optional): seconds since the player joined, sent as the step's first custom field
-- (FirstHatch and FirstSell carry it: how fast the opening gets there).
function Analytics.funnel(player: Player, data: any, stepName: string, seconds: number?)
	if data.funnel[stepName] then
		return
	end
	data.funnel[stepName] = true
	if Analytics.funnelObserver then
		Analytics.funnelObserver(player, stepName, seconds)
	end
	pcall(function()
		local other = Analytics.OtherFunnels[stepName]
		if other then
			AnalyticsService:LogFunnelStepEvent(player, other, nil, 1, stepName)
		else
			local fields = if seconds
				then { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "seconds=" .. math.floor(seconds) }
				else nil
			AnalyticsService:LogOnboardingFunnelStepEvent(player, Analytics.Funnel[stepName], stepName, fields)
		end
	end)
end

-- Tests: called with (player, eventName, value) for every custom event (nil in the game).
Analytics.observer = nil :: ((Player, string, number) -> ())?

local function custom(player: Player, eventName: string, value: number)
	if Analytics.observer then
		Analytics.observer(player, eventName, value)
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value)
	end)
end

-- Hatch outcomes: one event per rarity hatched and one per mutation on it (the odds players
-- actually see). Scripted outcomes (the onboarding's first hatch) never count.
function Analytics.hatch(player: Player, item: { rarity: string, mutations: { string }, scripted: string? })
	if item.scripted then
		return
	end
	custom(player, "Hatch_" .. item.rarity, 1)
	for _, m in item.mutations do
		custom(player, "Mutation_" .. m, 1)
	end
end

-- Batching (the offline Auto-Harvest replay can sell and rebuy thousands of eggs in one frame,
-- far past AnalyticsService's rate limit): between beginBatch and flush, a player's economy
-- events are summed per (flow, currency, type, sku) and logged once each by flush, with the
-- last ending balance. Balances themselves are never batched, only the logging.
type Pending = {
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	sku: string?,
}
local batches: { [Player]: { order: { string }, byKey: { [string]: Pending } } } = {}

function Analytics.beginBatch(player: Player)
	batches[player] = { order = {}, byKey = {} }
end

function Analytics.flush(player: Player)
	local batch = batches[player]
	batches[player] = nil
	if not batch then
		return
	end
	for _, key in batch.order do
		local e = batch.byKey[key]
		Analytics.economy(player, e.flow, e.currency, e.amount, e.endingBalance, e.transactionType, e.sku)
	end
end

-- flow: "Source" (currency in) or "Sink" (currency out).
-- transactionType: an Enum.AnalyticsEconomyTransactionType name, e.g. "Gameplay" or "Shop".
function Analytics.economy(
	player: Player,
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	sku: string?
)
	local batch = batches[player]
	if batch then
		local key = table.concat({ flow, currency, transactionType, sku or "" }, "|")
		local e = batch.byKey[key]
		if e then
			e.amount += amount
			e.endingBalance = endingBalance
		else
			batch.byKey[key] = {
				flow = flow,
				currency = currency,
				amount = amount,
				endingBalance = endingBalance,
				transactionType = transactionType,
				sku = sku,
			}
			table.insert(batch.order, key)
		end
		return
	end
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType[flow],
			currency,
			amount,
			endingBalance,
			transactionType,
			sku
		)
	end)
end

return Analytics
