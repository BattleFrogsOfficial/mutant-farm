--!strict
-- Server weather schedule (WeatherService). The next/current event is replicated as Workspace
-- attributes: WeatherNextId, WeatherNextAt, WeatherId, WeatherEndsAt.

return {
	minIntervalSeconds = 20 * 60,
	maxIntervalSeconds = 30 * 60,
	announceSeconds = 5 * 60,
	firstEventSeconds = 6 * 60, -- after a server starts
	-- While an event runs, every growing egg rolls this often for the event's mutation
	-- (x luck, capped), and can only gain it once.
	rollEverySeconds = 30,
	chancePerRoll = 0.15, -- default; an event can set its own
	events = {
		AcidRain = {
			name = "Acid Rain",
			icon = "☢",
			color = "#7CFF4A",
			mutation = "Radioactive",
			chancePerRoll = 0.1, -- ~27% per egg over a 90 s event
			weight = 50,
			durationSeconds = 90,
		},
		SolarFlare = {
			name = "Solar Flare",
			icon = "☀",
			color = "#FFD24A",
			mutation = "Golden",
			chancePerRoll = 0.15, -- ~39%
			weight = 40,
			durationSeconds = 90,
		},
		GlitchStorm = {
			name = "Glitch Storm",
			icon = "⚡",
			color = "#FF3CF0",
			mutation = "Glitched",
			chancePerRoll = 0.05, -- ~10% over 60 s: rare
			weight = 10,
			durationSeconds = 60,
			discordAlert = true,
		},
	},
}
