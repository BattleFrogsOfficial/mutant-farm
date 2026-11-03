--!strict
-- Auto-Harvest while you're away: replays the plot's grow cycles in time order (mature -> hatch ->
-- sell it if it's Game.autoSellRarity, else keep it in the bag, or let it wait on its patch when
-- the bag is full -> replant patches whose toggle is on) from when you left, for at most
-- Game.autoHarvestOfflineHours. GrowthService supplies `cycle`, which settles every slot to a time
-- and runs one Auto-Harvest pass then; this module only finds the next maturity and the window.

local Growth = require(script.Parent.Growth)
local GameConfig = require(script.Parent.Config.Game)

local AutoHarvest = {}

-- Safety net: the window is at most autoHarvestOfflineHours, and each pass moves time forward to
-- the next maturity (40 patches of 1-minute eggs for 8 h is under 20K passes).
local MAX_CYCLES = 100_000

export type Slot = { eggId: string, rarity: string, growth: number, updatedAt: number }

-- What Auto-Harvest does with a mature egg of `rarity`: "sell" it at once (Game.autoSellRarity,
-- no bag room needed), "keep" it in the bag, or let it "wait" on its patch (the bag is full).
function AutoHarvest.decide(rarity: string, bagCount: number, bagCap: number): "sell" | "keep" | "wait"
	if rarity == GameConfig.autoSellRarity then
		return "sell"
	end
	return if bagCount < bagCap then "keep" else "wait"
end

-- The next time after `at` when a slot that is still growing at `at` matures (mature slots are
-- skipped: they were harvested at `at`, or wait for bag space). nil when nothing is growing.
function AutoHarvest.nextMature(slots: { [string]: Slot }, at: number, water: Growth.Water, speed: number): number?
	local best: number? = nil
	for _, slot in slots do
		local required = Growth.requiredSeconds(slot.eggId, slot.rarity)
		local grown = Growth.advance(slot.growth, slot.updatedAt, at, water, speed)
		if required - grown > 1e-6 then
			local when = at + Growth.secondsRemaining(grown, required, at, water, speed)
			if best == nil or when < best then
				best = when
			end
		end
	end
	return best
end

-- The end of the offline replay: `to`, or `from` + Game.autoHarvestOfflineHours if that's sooner.
function AutoHarvest.windowEnd(from: number, to: number): number
	return math.min(to, from + GameConfig.autoHarvestOfflineHours * 3600)
end

-- Runs one pass at `from` (eggs that were already mature, empty toggled patches), then one at
-- every maturity up to `to`. `cycle(at)` must settle the plot to `at` and run an Auto-Harvest
-- pass; it returns how many it hatched. Returns the total hatched.
function AutoHarvest.run(
	plot: { slots: { [string]: Slot }, water: Growth.Water, speed: number },
	from: number,
	to: number,
	cycle: (at: number) -> number
): number
	local total, t = cycle(from), from
	for _ = 1, MAX_CYCLES do
		local at = AutoHarvest.nextMature(plot.slots, t, plot.water, plot.speed)
		if at == nil or at > to then
			break
		end
		total += cycle(at)
		t = at
	end
	return total
end

return AutoHarvest
