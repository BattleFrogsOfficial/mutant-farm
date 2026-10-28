--!strict
-- Developer products (Robux) and Gem-priced items. Replace id = 0 with real IDs from Creator Hub.
-- Wired up in M3 (packs, potion, skip, bundle) and M5 (instant weather, rebirth now, limited eggs).

return {
	robux = {
		Gems100 = { id = 0, price = 49, gems = 100 },
		Gems550 = { id = 0, price = 199, gems = 550, tag = "Best value" },
		Gems1500 = { id = 0, price = 499, gems = 1_500 },
		Gems4000 = { id = 0, price = 999, gems = 4_000 },
		StarterBundle = {
			id = 0,
			price = 599,
			-- Luck Potions arrive with the potion system; until then the bundle grants their Gem value.
			grants = { passes = { "Luck2x", "AutoHarvest" }, gems = 550 },
			offerSeconds = 10 * 60, -- shown once, in the first 10 minutes, never again
		},
	},
	gems = {
		LuckPotion = { cost = 25, durationSeconds = 30 * 60, luck = 3 },
		-- SOFT-LAUNCH TUNING FLAG: priced per egg on its own time left, so a full plot of 8 h Cosmic
		-- eggs clears for ~120 Robux of Gems. If Skip revenue is high while day-3 return is low, it's
		-- eating the timers that bring people back: price on total remaining minutes instead.
		SkipTimer = { costPer10Minutes = 5 },
		-- A 120 s weather event (any of Config/Weather's) on your own plot only. Policy-gated.
		InstantWeather = { cost = 400 },
		-- Rebirth without the full Cash: offered from minFraction of the cost (50%) up. Not random,
		-- so not policy-gated.
		RebirthNow = { cost = 100, minFraction = 0.5 },
		LimitedEgg = { minCost = 500, maxCost = 1_500 },
	},
}
