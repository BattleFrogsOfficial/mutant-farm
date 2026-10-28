--!strict
-- Rebirth costs: Rebirth 1 costs firstCost (tuned so the first rebirth lands at 35-45 minutes of
-- active play with Starter, Swamp and Lab), each later one costGrowth x the previous
-- (250K, 1.25M, 6.25M, 31.25M, ...). Each rebirth adds +cashBonusPerRebirth to the Cash
-- multiplier (additive: Rebirth 4 = 3x, Rebirth 10 = 6x). Check pacing with `lune run tools/sim`.

return {
	cashBonusPerRebirth = 0.5,
	firstCost = 250_000,
	costGrowth = 5,
}
