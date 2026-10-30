-- Upgrades panel (UI/UpgradesPanel): every upgrade at level 0 (prices on every button), and every
-- one maxed (grey MAX; Offline Mutations MAX through the pass). The default mock is in between.
return function(api)
	local State, set = api.State, api.set
	set(State.panel, "upgrades")

	local zero = table.clone(api.snapshot)
	zero.gems = 5_000
	zero.upgrades = { growthSpeed = 0, mutationOdds = 0 }
	zero.upgradeCosts = { growthSpeed = 2_000, mutationOdds = 2_000 }
	zero.gemUpgrades = { penSlots = 0, luck = 0, offline = 0 }
	set(State.snapshot, zero)
	api.capture("upgrades-0")

	local max = table.clone(api.snapshot)
	max.upgrades = { growthSpeed = 5, mutationOdds = 5 }
	max.upgradeCosts = {}
	max.gemUpgrades = { penSlots = 1, luck = 3, offline = 1 }
	max.penCapacity = 12
	max.ownedPasses = { OfflineMutations = true }
	set(State.snapshot, max)
	api.capture("upgrades-max")

	api.reset()
end
