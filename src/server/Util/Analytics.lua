--!strict
-- Thin wrapper over AnalyticsService. Analytics must never break gameplay, so every call is pcall'd.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

-- First-session funnel. Steps must be logged in order and once per player.
Analytics.Funnel = {
	Joined = 1,
	FirstPlant = 2,
	FirstHarvest = 3,
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

function Analytics.funnel(player: Player, data: any, stepName: string)
	if data.funnel[stepName] then
		return
	end
	data.funnel[stepName] = true
	pcall(function()
		local other = Analytics.OtherFunnels[stepName]
		if other then
			AnalyticsService:LogFunnelStepEvent(player, other, nil, 1, stepName)
		else
			AnalyticsService:LogOnboardingFunnelStepEvent(player, Analytics.Funnel[stepName], stepName)
		end
	end)
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
