--!strict
-- Auto-Harvest while you're away: replays the plot's grow cycles in time order (mature -> harvest
-- to bag -> replant the same egg) from when you left to now. GrowthService supplies `cycle`, which
-- settles every slot to a time and harvests/replants whatever is mature then; this module only
-- finds the next maturity and stops when nothing more can happen.

local Growth = require(script.Parent.Growth)

local AutoHarvest = {}

-- Safety net: 40 slots x 1-minute eggs for a week is ~400K cycles, but the bag (200) fills long
-- before; harvesting stops the loop as soon as a cycle harvests nothing.
local MAX_CYCLES = 100_000

export type Slot = { eggId: string, rarity: string, growth: number, updatedAt: number }

-- Earliest server time, at or after `at`, when a slot is (or was) mature. nil when no slots.
function AutoHarvest.nextMature(slots: { [string]: Slot }, at: number, wateredUntil: number, speed: number): number?
	local best: number? = nil
	for _, slot in slots do
		local required = Growth.requiredSeconds(slot.eggId, slot.rarity)
		local grown = Growth.advance(slot.growth, slot.updatedAt, at, wateredUntil, speed)
		local when = at + Growth.secondsRemaining(grown, required, at, wateredUntil, speed)
		if best == nil or when < best then
			best = when
		end
	end
	return best
end

-- Runs cycles from `from` to `to`. `cycle(at)` must settle the plot to `at`, harvest every mature
-- slot and replant; it returns how many it harvested. Returns the total harvested.
function AutoHarvest.run(
	plot: { slots: { [string]: Slot }, wateredUntil: number, speed: number },
	from: number,
	to: number,
	cycle: (at: number) -> number
): number
	local total, t = 0, from
	for _ = 1, MAX_CYCLES do
		local at = AutoHarvest.nextMature(plot.slots, t, plot.wateredUntil, plot.speed)
		if at == nil or at > to then
			break
		end
		local harvested = cycle(at)
		if harvested == 0 then
			break -- bag full (or nothing could be harvested): nothing more will happen
		end
		total += harvested
		t = at
	end
	return total
end

return AutoHarvest
