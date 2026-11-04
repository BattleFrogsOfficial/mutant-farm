--!strict
-- The first five minutes (2026-11-03): a scripted opening that shows the whole loop inside
-- ~90 seconds. Rules in shared/Onboarding.lua; the server (OnboardingService, GrowthService,
-- EconomyService) applies them only to profiles created with `enabled` on, and never again.

return {
	enabled = true,

	-- A new profile starts with this egg already growing on patch `slot`, `secondsLeft` from
	-- hatching, plus `bag` in the bag (instead of Game.startingEggs).
	preplant = { egg = "Starter", slot = 1, secondsLeft = 10 },
	bag = { Starter = 1 },

	-- The first hatch of a new profile, from this fixed table (not rolled): a Starter Common at
	-- size 0.8 with Glitched (+8: x9), its value scaled by firstHatchValueScale after everything
	-- else (Valuation): 80 x 0.8 x 9 x 0.2 = $115 ($13 before the Glitched). Full cutscene, never Fast Hatch; a FIRST HATCH BONUS
	-- ribbon on the reveal and its Almanac entry. Excluded from mutation analytics and Top Pens.
	firstHatch = { rarity = "Common", mutations = { "Glitched" }, size = 0.8 },
	firstHatchValueScale = 0.2,
	firstHatchRibbon = "FIRST HATCH BONUS",

	-- The first sale's toast ($115 + the $100 start buys 2 Starter eggs; patch 7 at $200 is next).
	firstSaleToast = "%s! Buy more eggs and grow your farm.",

	-- Starter eggs planted before the Nth hatch grow in `seconds` (as a Common; rarity still
	-- stretches it) instead of the tier's 60 s; from hatch 30 on, the normal time.
	rampEgg = "Starter",
	growRamp = {
		{ hatches = 10, seconds = 10 },
		{ hatches = 20, seconds = 20 },
		{ hatches = 30, seconds = 30 },
	},

	-- The tutorial's "buy eggs" step: a BUY button on the egg tray (the usual BuyEgg intent) until
	-- the player has opened the Egg Shop once.
	trayBuy = { egg = "Starter", quantity = 2 },

	-- A free Solar Flare on the player's own plot (the Instant Weather path, cost 0), once per
	-- profile: the first moment `minGrowing` eggs are growing after `afterSeconds` of play, unless a
	-- global event runs or starts within `clearSeconds`.
	soloWeather = {
		event = "SolarFlare",
		afterSeconds = 150,
		minGrowing = 3,
		clearSeconds = 300,
		toast = "A Solar Flare hit your farm! Golden odds up for 2 minutes.",
	},
}
