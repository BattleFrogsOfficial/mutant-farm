--!strict
-- Rebirth costs: Rebirth 1 costs firstCost, each later one costGrowth x the previous
-- (700K, 3.15M, 14.2M, 63.8M, 287M, 1.29B, 5.81B, 26.2B, 118B, 530B, 2.38T, 10.7T, ...).
-- x4.5 again since 2026-11-05 (x6.5 from 2026-11-03): the grow ramp is gone and the growth
-- circle is softer (3.55x offers, a 3-8 s vanish), so the curve goes back to x4.5. The
-- requirement is Cash earned this life (2026-11-04). Each rebirth adds +cashBonusPerRebirth to
-- the Cash multiplier (additive: Rebirth 4 = 3x, Rebirth 10 = 6x). Check pacing with
-- `lune run tools/sim` (`--all`, `--taps`, `--hours`).

return {
	cashBonusPerRebirth = 0.5,
	firstCost = 700_000,
	costGrowth = 4.5,
}
