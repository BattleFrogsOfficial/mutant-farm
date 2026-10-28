--!strict
-- Size bands. A band is picked by weight, then a size is picked uniformly inside it.
-- Luck multiplies the weights of bands marked luckBoosted, then weights renormalize.

return {
	-- How big a mutant LOOKS (value still uses the 0.8x-3x size above). Visual scale =
	-- tierScale x rarityScale x species.scale x size ^ sizeExponent, so a Titan Cosmic
	-- Legendary towers ~40x over a Starter Common. Giants are the flex.
	visual = {
		tierScale = { Starter = 1, Swamp = 1.2, Lab = 1.45, Toxic = 1.75, Void = 2.1, Cosmic = 2.6 },
		rarityScale = { Common = 1, Uncommon = 1.15, Rare = 1.35, Epic = 1.7, Legendary = 2.4 },
		sizeExponent = 1.6,
	},
	bands = {
		{ min = 0.8, max = 1.0, weight = 25, luckBoosted = false },
		{ min = 1.0, max = 1.3, weight = 55, luckBoosted = false },
		{ min = 1.3, max = 2.0, weight = 17, luckBoosted = false },
		{ min = 2.0, max = 2.9, weight = 2.5, luckBoosted = true },
		{ min = 3.0, max = 3.0, weight = 0.5, luckBoosted = true, label = "Titan" },
	},
}
