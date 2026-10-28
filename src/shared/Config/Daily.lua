--!strict
-- Daily login streak: claim once per UTC day. Missing a day resets to day 1; after day 7 it loops.
-- kind "eggs" grants eggs (any tier; a locked tier is a taste of what's next).
-- kind "cash" grants `minutes` of the player's current $/min, at least `min`.
-- Gems join these rewards once Gems exist (M3).

return {
	rewards = {
		{ kind = "eggs", egg = "Starter", count = 3, label = "3 Starter Eggs" },
		{ kind = "eggs", egg = "Swamp", count = 2, label = "2 Swamp Eggs" },
		{ kind = "cash", minutes = 10, min = 1_000, label = "10 min of Cash" },
		{ kind = "eggs", egg = "Swamp", count = 4, label = "4 Swamp Eggs" },
		{ kind = "eggs", egg = "Lab", count = 1, label = "1 Lab Egg" },
		{ kind = "cash", minutes = 20, min = 2_500, label = "20 min of Cash" },
		{ kind = "eggs", egg = "Toxic", count = 1, label = "1 TOXIC EGG" },
	},
	-- Away at least this long to get the "Welcome back" summary.
	welcomeBackSeconds = 10 * 60,
}
