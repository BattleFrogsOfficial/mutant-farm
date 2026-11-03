--!strict
-- Rebirth costs: Rebirth 1 costs firstCost, each later one costGrowth x the previous
-- (700K, 4.55M, 29.6M, 192M, 1.25B, 8.1B, 52.8B, 343B, 2.23T, 14.5T, 94T, 612T, ...).
-- x6.5 since 2026-11-03 (was x4.5): a player with every pass who taps every growth boost reached
-- Rebirth 10 in ~7 hours of play (one night); now ~19 h (free ~74 h), and the Magma (Rebirth 9)
-- and Quantum (Rebirth 11) tiers give the late game new eggs to reach. 700K keeps the first
-- rebirth where it was (~25 simulator minutes on the water pad, ~10 tapping every boost). Each
-- rebirth adds +cashBonusPerRebirth to the Cash multiplier (additive: Rebirth 4 = 3x, Rebirth
-- 10 = 6x). Check pacing with `lune run tools/sim` (`--all`, `--taps`, `--hours`).

return {
	cashBonusPerRebirth = 0.5,
	firstCost = 700_000,
	costGrowth = 6.5,
}
