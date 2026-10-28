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
