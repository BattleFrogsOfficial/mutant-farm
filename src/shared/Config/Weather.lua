--!strict
-- Server weather schedule (WeatherService). The next/current event is replicated as Workspace
-- attributes: WeatherNextId, WeatherNextAt, WeatherId, WeatherEndsAt.

return {
	minIntervalSeconds = 20 * 60,
	maxIntervalSeconds = 30 * 60,
	announceSeconds = 5 * 60,
	firstEventSeconds = 6 * 60, -- after a server starts
	-- While an event runs, every growing egg rolls for the event's mutation (x luck, capped at
	-- maxChance) every rollEverySeconds, starting the moment it begins: a 120 s event is 4 rolls,
	-- and an egg can only gain the mutation once. Over a whole event that's 1 - (1 - p)^4.
	rollEverySeconds = 30,
	maxChance = 0.9,
	-- Glitch Storm is the rare one: weight 20 of 120 = 1 event in 6.
	events = {
		AcidRain = {
			name = "Acid Rain",
			icon = "☢",
			color = "#7CFF4A",
			mutation = "Radioactive",
			chancePerRoll = 0.25, -- ~68% of eggs growing through the whole event
			weight = 50,
			durationSeconds = 120,
		},
		SolarFlare = {
			name = "Solar Flare",
			icon = "☀",
			color = "#FFD24A",
			mutation = "Golden",
			chancePerRoll = 0.3, -- ~76%
			weight = 50,
			durationSeconds = 120,
		},
		GlitchStorm = {
			name = "Glitch Storm",
			icon = "⚡",
			color = "#FF3CF0",
			mutation = "Glitched",
			chancePerRoll = 0.1, -- ~34%
			weight = 20,
			durationSeconds = 120,
			discordAlert = true,
		},
	},
	-- Fixed order for the weighted pick (table iteration order isn't).
	order = { "AcidRain", "SolarFlare", "GlitchStorm" },
}
