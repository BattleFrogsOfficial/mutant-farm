--!strict
-- Size bands. A band is picked by weight, then a size is picked uniformly inside it.
-- Luck multiplies the weights of bands marked luckBoosted, then weights renormalize.

return {
	bands = {
		{ min = 0.8, max = 1.0, weight = 25, luckBoosted = false },
		{ min = 1.0, max = 1.3, weight = 55, luckBoosted = false },
		{ min = 1.3, max = 2.0, weight = 17, luckBoosted = false },
		{ min = 2.0, max = 2.9, weight = 2.5, luckBoosted = true },
		{ min = 3.0, max = 3.0, weight = 0.5, luckBoosted = true, label = "Titan" },
	},
}
