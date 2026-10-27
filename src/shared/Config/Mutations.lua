--!strict
-- Mutations. Every mutant gets `rollsPerGrow` rolls spaced evenly across its grow time.
-- Each roll checks every mutation independently at chancePerRoll x luck.
-- Mutations multiply each other; each type can appear at most once per mutant.

local Mutations = {}

Mutations.rollsPerGrow = 10

Mutations.order = { "Shiny", "Golden", "Radioactive", "Glitched", "Cosmic" }

Mutations.info = {
	Shiny = { multiplier = 2, chancePerRoll = 0.015, color = "#FFFFFF" },
	Golden = { multiplier = 5, chancePerRoll = 0.006, color = "#FFD24A" },
	Radioactive = { multiplier = 10, chancePerRoll = 0.0025, color = "#7CFF4A" },
	Glitched = { multiplier = 25, chancePerRoll = 0.0008, color = "#FF3CF0" },
	Cosmic = { multiplier = 100, chancePerRoll = 0.0001, color = "#3B1A78" },
}

return Mutations
