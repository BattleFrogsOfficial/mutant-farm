--!strict
-- Rebirth thresholds. costs[n] is the Cash needed to perform rebirth number n
-- (costs[1] takes a fresh player to Rebirth 1). Rebirths 1-6 come from `lune run tools/sim -- --suggest`
-- (bisects each cost until the bot needs targetPhaseMinutes of active play); 7-10 were raised by hand
-- because Cosmic income snowballs, then checked with `lune run tools/sim` against the day targets.
-- Rebirth is implemented in M4; the table is here so the simulator and UI share it.

return {
	cashBonusPerRebirth = 0.5, -- additive: Rebirth 4 = 3x, Rebirth 10 = 6x
	-- Active minutes each rebirth should take from a fresh reset. 40 min for the first,
	-- ~90 min through Void (Rebirth 4 on day 3-4 at 1.5h/day), then longer toward ~3 weeks for Rebirth 10.
	targetPhaseMinutes = { 40, 90, 90, 90, 150, 180, 210, 240, 270, 300 },
	-- Each cost is at least this multiple of the one before.
	minCostGrowth = 1.5,
	costs = {
		800_000,
		20_000_000,
		90_000_000,
		140_000_000,
		530_000_000,
		1_600_000_000,
		4_000_000_000,
		25_000_000_000,
		100_000_000_000,
		400_000_000_000,
	},
	-- Beyond the table, each rebirth costs this multiple of the previous one.
	costGrowthAfterTable = 2,
}
