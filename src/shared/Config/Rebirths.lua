--!strict
-- Rebirth costs: Rebirth 1 costs firstCost, each later one costGrowth x the previous
-- (700K, 3.5M, 17.5M, 87.5M, ...). 700K puts the first rebirth at ~25 minutes of the simulator's
-- perfect play with Starter, Swamp and Lab, which is ~33-40 real minutes once a player walks,
-- reads, idles and watches hatches (the 35-45 minute target). Each rebirth adds +cashBonusPerRebirth to the Cash
-- multiplier (additive: Rebirth 4 = 3x, Rebirth 10 = 6x). Check pacing with `lune run tools/sim`.

return {
	cashBonusPerRebirth = 0.5,
	firstCost = 700_000,
	costGrowth = 5,
}
