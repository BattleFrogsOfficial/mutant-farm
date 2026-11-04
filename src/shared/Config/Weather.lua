--!strict
-- Weather events. The schedule is global: a pure function of wall-clock time (shared/Weather.lua
-- scheduleAt), so every server runs the same event at the same moment. Time is cut into
-- bucketSeconds buckets counted from the unix epoch (one an hour since 2026-11-04, on the hour);
-- each bucket's event starts offsetSeconds in and lasts its durationSeconds; its
-- type is a seeded hash of the bucket index, weighted by `weight`. WeatherService replicates the
-- current/next event as Workspace attributes: WeatherNextId, WeatherNextAt, WeatherId,
-- WeatherEndsAt, and announces it (toasts at T-5:00, T-1:00 and the start, a chat line at T-5:00;
-- Glitch Storm also goes to Discord through the relay, Config/Game relayUrl).

return {
	bucketSeconds = 3600, -- an event every hour
	offsetSeconds = 300, -- 5 minutes into its bucket
	seed = 20261028, -- mixed into the bucket hash: change it to reshuffle the whole schedule
	announceSeconds = 5 * 60, -- the HUD chip, the first toast, the chat line and Discord
	warnSeconds = 60, -- the last toast before it starts
	-- ONE roll per growing egg per event (2026-11-04): every egg growing while it runs (also one
	-- planted mid-event) rolls once for the event's mutation at chancePerRoll x luck, capped at
	-- maxChance. An egg that already has that mutation can't get it again.
	maxChance = 0.6,
	-- Weights (%): Acid Rain 45, Solar Flare 40, Glitch Storm 15 (the rare one).
	events = {
		AcidRain = {
			name = "Acid Rain",
			icon = "☢", -- chat lines and the server toasts' text
			glyph = "radiation", -- UI/Icons, in the HUD and panels
			color = "#7CFF4A",
			mutation = "Radioactive",
			chancePerRoll = 0.2, -- the one roll per egg
			weight = 45,
			durationSeconds = 120,
			-- Server-wide toasts (%s = the countdown, m:ss) and the T-5:00 chat line.
			soon = "%s Acid Rain in %s — plant now!",
			start = "%s Acid Rain is here! a Radioactive (+4) roll for every growing egg",
		},
		SolarFlare = {
			name = "Solar Flare",
			icon = "☀",
			glyph = "sun",
			color = "#FFD24A",
			mutation = "Golden",
			chancePerRoll = 0.25,
			weight = 40,
			durationSeconds = 120,
			soon = "%s Solar Flare in %s — plant now!",
			start = "%s Solar Flare is here! a Golden (+2) roll for every growing egg",
		},
		GlitchStorm = {
			name = "Glitch Storm",
			icon = "⚡",
			glyph = "bolt",
			color = "#FF3CF0",
			-- Radioactive since 2026-11-04: Glitched comes only from the base rolls.
			mutation = "Radioactive",
			chancePerRoll = 0.4,
			weight = 15,
			durationSeconds = 120,
			soon = "%s Glitch Storm in %s — plant now!",
			start = "%s Glitch Storm is here! a big Radioactive (+4) roll for every growing egg",
			-- Posted to Discord at T-5:00 by one server (MemoryStore claim) via the relay.
			discordAlert = true,
		},
	},
	-- Fixed order for the weighted pick (table iteration order isn't).
	order = { "AcidRain", "SolarFlare", "GlitchStorm" },
}
