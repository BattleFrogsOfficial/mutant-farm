--!strict
-- Rarity multipliers. Colors follow the platform convention (grey, green, blue, purple, gold).

local Rarities = {}

Rarities.order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

Rarities.info = {
	Common = { valueMultiplier = 1, growMultiplier = 1, color = "#B4B8C2" },
	Uncommon = { valueMultiplier = 3, growMultiplier = 1.25, color = "#5BD15B" },
	Rare = { valueMultiplier = 10, growMultiplier = 1.5, color = "#4A9DFF" },
	Epic = { valueMultiplier = 40, growMultiplier = 2, color = "#B05CFF" },
	Legendary = { valueMultiplier = 250, growMultiplier = 3, color = "#FFD24A" },
}

return Rarities
