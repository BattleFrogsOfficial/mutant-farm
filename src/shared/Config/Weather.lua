--!strict
-- Server weather schedule. Wired up in M4.

return {
	minIntervalSeconds = 20 * 60,
	maxIntervalSeconds = 30 * 60,
	announceSeconds = 5 * 60,
	events = {
		AcidRain = { name = "Acid Rain", mutation = "Radioactive", weight = 50, durationSeconds = 90 },
		SolarFlare = { name = "Solar Flare", mutation = "Golden", weight = 40, durationSeconds = 90 },
		GlitchStorm = {
			name = "Glitch Storm",
			mutation = "Glitched",
			weight = 10,
			durationSeconds = 60,
			discordAlert = true,
		},
	},
}
