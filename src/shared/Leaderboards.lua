--!strict
-- The two global boards in the hub: Top Pens (what the mutants standing in your pen are worth)
-- and Top Rebirths. LeaderboardService saves and reads them (OrderedDataStore); clients draw
-- them and the viewer's own row. Pure helpers shared by both sides.

local Valuation = require(script.Parent.Valuation)

local Leaderboards = {}

Leaderboards.SIZE = 100 -- entries per board
Leaderboards.BOARDS = { "pens", "rebirths" }

export type Entry = { userId: number, name: string, value: number }

-- OrderedDataStore values are integers; anything past 2^53 loses precision anyway.
local MAX_VALUE = 2 ^ 53

-- Pen value: the sell value of the pen's mutants at x1 (tier x rarity x mutations x size, no
-- Cash multiplier), so the board compares mutants, not rebirth counts.
function Leaderboards.penValue(penItems: { Valuation.Mutant }): number
	local total = 0
	for _, item in penItems do
		total += Valuation.sellValue(item, 1)
	end
	return math.floor(math.min(total, MAX_VALUE))
end

function Leaderboards.storeValue(value: number): number
	return math.floor(math.clamp(value, 0, MAX_VALUE))
end

-- The viewer's rank on a board: their position when they're in the top list, nil when not
-- ("100+" on the board).
function Leaderboards.rankOf(entries: { Entry }, userId: number): number?
	for i, entry in entries do
		if entry.userId == userId then
			return i
		end
	end
	return nil
end

return Leaderboards
