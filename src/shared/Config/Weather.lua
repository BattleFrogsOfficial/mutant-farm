--!strict
-- Weather events. The schedule is global: a pure function of wall-clock time (shared/Weather.lua
-- scheduleAt), so every server runs the same event at the same moment. Time is cut into
-- bucketSeconds buckets counted from the unix epoch (an hour boundary, so the grid meets the hour
-- again every 5 h); each bucket's event starts offsetSeconds in and lasts its durationSeconds; its
-- type is a seeded hash of the bucket index, weighted by `weight`. WeatherService replicates the
-- current/next event as Workspace attributes: WeatherNextId, WeatherNextAt, WeatherId,
-- WeatherEndsAt, and announces it (toasts at T-5:00, T-1:00 and the start, a chat line at T-5:00;
-- Glitch Storm also goes to Discord through the relay, Config/Game relayUrl).

return {
	bucketSeconds = 1500, -- an event every 25 minutes
	offsetSeconds = 300, -- 5 minutes into its bucket
	seed = 20261028, -- mixed into the bucket hash: change it to reshuffle the whole schedule
	announceSeconds = 5 * 60, -- the HUD chip, the first toast, the chat line and Discord
	warnSeconds = 60, -- the last toast before it starts
	-- While an event runs, every growing egg rolls for the event's mutation (x luck, capped at
	-- maxChance) every rollEverySeconds, starting the moment it begins: a 120 s event is 4 rolls,
	-- and an egg can only gain the mutation once. Over a whole event that's 1 - (1 - p)^4.
	rollEverySeconds = 30,
	maxChance = 0.9,
	-- Weights (%): Acid Rain 45, Solar Flare 40, Glitch Storm 15 (the rare one).
	events = {
		AcidRain = {
			name = "Acid Rain",
			icon = "☢",
			color = "#7CFF4A",
			mutation = "Radioactive",
			chancePerRoll = 0.25, -- ~68% of eggs growing through the whole event
			weight = 45,
			durationSeconds = 120,
			-- Server-wide toasts (%s = the countdown, m:ss) and the T-5:00 chat line.
			soon = "%s Acid Rain in %s — plant now!",
			start = "%s Acid Rain is here! Radioactive x10 odds on every growing egg",
		},
		SolarFlare = {
			name = "Solar Flare",
			icon = "☀",
			color = "#FFD24A",
			mutation = "Golden",
			chancePerRoll = 0.3, -- ~76%
			weight = 40,
			durationSeconds = 120,
			soon = "%s Solar Flare in %s — plant now!",
			start = "%s Solar Flare is here! Golden x5 odds on every growing egg",
		},
		GlitchStorm = {
			name = "Glitch Storm",
			icon = "⚡",
			color = "#FF3CF0",
			mutation = "Glitched",
			chancePerRoll = 0.1, -- ~34%
			weight = 15,
			durationSeconds = 120,
			soon = "%s Glitch Storm in %s — plant now!",
			start = "%s Glitch Storm is here! Glitched x25 odds on every growing egg",
			-- Posted to Discord at T-5:00 by one server (MemoryStore claim) via the relay.
			discordAlert = true,
		},
	},
	-- Fixed order for the weighted pick (table iteration order isn't).
	order = { "AcidRain", "SolarFlare", "GlitchStorm" },
}
