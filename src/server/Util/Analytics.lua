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
	FirstPurchasePrompt = 6, -- M3
}

function Analytics.funnel(player: Player, data: any, stepName: string)
	if data.funnel[stepName] then
		return
	end
	data.funnel[stepName] = true
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, Analytics.Funnel[stepName], stepName)
	end)
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
