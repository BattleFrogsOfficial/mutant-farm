--!strict
-- Mutations. Every mutant gets `rollsPerGrow` rolls spaced evenly across its grow time.
-- Each roll checks every mutation independently at chancePerRoll x luck.
-- Mutations are ADDITIVE bonuses (2026-11-04): value x (1 + the sum of the bonuses on it), so a
-- full set is x(1 + 1 + 2 + 4 + 8 + 20) = x36. Each type can appear at most once per mutant.

local Mutations = {}

Mutations.rollsPerGrow = 10

Mutations.order = { "Shiny", "Golden", "Radioactive", "Glitched", "Cosmic" }

Mutations.info = {
	Shiny = { bonus = 1, chancePerRoll = 0.015, color = "#FFFFFF" },
	Golden = { bonus = 2, chancePerRoll = 0.006, color = "#FFD24A" },
	Radioactive = { bonus = 4, chancePerRoll = 0.0025, color = "#7CFF4A" },
	Glitched = { bonus = 8, chancePerRoll = 0.0008, color = "#FF3CF0" },
	Cosmic = { bonus = 20, chancePerRoll = 0.0001, color = "#3B1A78" },
}

return Mutations
