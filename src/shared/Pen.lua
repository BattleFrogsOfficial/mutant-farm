--!strict
-- Which mutants stand in the pen. Pinned mutants always do (up to the pen's size); the rest of
-- the pen fills with the most valuable unpinned mutants in the bag. Used by the server (pen
-- display, pen income, rebirth) and the client (bag UI) so both agree.

local Valuation = require(script.Parent.Valuation)

local Pen = {}

export type Item = Valuation.Mutant & { id: string, pinned: boolean? }

-- Most valuable first; ties broken by id (oldest first) so the pen doesn't reshuffle.
local function byValue(a: Item, b: Item): boolean
	local va, vb = Valuation.sellValue(a, 1), Valuation.sellValue(b, 1)
	if va ~= vb then
		return va > vb
	end
	return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
end

function Pen.pinnedCount(inventory: { [string]: Item }): number
	local n = 0
	for _, item in inventory do
		if item.pinned then
			n += 1
		end
	end
	return n
end

-- Can one more mutant be pinned? Pins are capped at the pen's size.
function Pen.canPin(inventory: { [string]: Item }, size: number): boolean
	return Pen.pinnedCount(inventory) < size
end

-- The pen's mutants, pinned ones first, at most `size`.
function Pen.select(inventory: { [string]: Item }, size: number): { Item }
	local pinned, rest = {}, {}
	for _, item in inventory do
		table.insert(if item.pinned then pinned else rest, item)
	end
	table.sort(pinned, byValue)
	table.sort(rest, byValue)
	local out = {}
	for _, list in { pinned, rest } do
		for _, item in list do
			if #out >= size then
				return out
			end
			table.insert(out, item)
		end
	end
	return out
end

-- Ids of the pen's mutants as a set.
function Pen.ids(inventory: { [string]: Item }, size: number): { [string]: boolean }
	local set = {}
	for _, item in Pen.select(inventory, size) do
		set[item.id] = true
	end
	return set
end

return Pen
