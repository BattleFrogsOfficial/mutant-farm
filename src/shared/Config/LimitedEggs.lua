--!strict
-- Limited-time eggs, sold for Gems in the Egg Shop only while now is inside [startsAt, endsAt]
-- (unix seconds, inclusive). Adding next week's egg = one entry here + its species in
-- Config/Mutants.lua (bucket = the egg's id). Nothing else.
--
-- Fields:
--   id, name, tagline (shop card), icon (emoji on the card, tray and bag), event (Almanac label:
--   "LIMITED · <event>"), color (UI swatch), design (shell look for MutantModel.buildEgg; the
--   pattern must be one MutantModel knows), priceGems (x5 = 5x), growSeconds (a Common's grow;
--   Rarities.growMultiplier stretches it), valueTier (whose base value its mutants sell at, and
--   whose size scale they use), rarityFrom + rarityBoost (odds = that tier's Uncommon-and-above
--   weights x boost, renormalized: the Gem-egg construction, so luck still applies on top under
--   the 6x cap) or an explicit odds table, banner (Egg Shop roof banner while active at server
--   start) and decor (props World builds around the fountain while active at server start).
--
-- Limited eggs are paid random items: hidden and refused where PolicyService restricts them.
-- Once the window closes the card leaves the shop; owned eggs stay plantable and hatchable, and
-- planted ones survive rebirth (back to the bag), like Gem eggs.

return {
	{
		id = "Pumpkin",
		name = "Pumpkin Egg",
		tagline = "Only until Nov 5",
		icon = "🎃", -- chat lines and world signs
		glyph = "pumpkin", -- UI/Icons, in the HUD and panels
		event = "Halloween 2026",
		color = "#FF8A1F",
		design = { pattern = "jack", shell = "#FF8A1F", accent = "#3A1A06" },
		priceGems = 600,
		growSeconds = 30 * 60,
		valueTier = "Lab",
		rarityFrom = "Lab",
		rarityBoost = 2,
		-- 2026-10-29 00:00 to 2026-11-05 23:59 America/New_York. Oct 29 is EDT (UTC-4); DST ends
		-- Nov 1, so Nov 5 is EST (UTC-5): 04:00 UTC Oct 29 to 04:59 UTC Nov 6.
		startsAt = 1_793_246_400,
		endsAt = 1_793_941_140,
		banner = "🎃 PUMPKIN EGG · ENDS NOV 5",
		decor = "pumpkins",
	},
}
