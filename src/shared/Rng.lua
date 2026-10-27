--!strict
-- Seeded PRNG (mulberry32) that behaves identically in Roblox and in Lune tests/sim.
-- Every random outcome that touches value (rarity, mutations, size) goes through here.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

-- 32-bit integer multiply without losing precision in doubles.
local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local hi = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return bit32.bor(0, aLo * bLo + bit32.lshift(hi, 16))
end

function Rng.new(seed: number): Rng
	return setmetatable({ state = bit32.bor(0, seed % 4294967296) }, Rng)
end

-- Float in [0, 1).
function Rng.next(self: Rng): number
	self.state = bit32.bor(0, self.state + 0x6D2B79F5)
	local t = imul(bit32.bxor(self.state, bit32.rshift(self.state, 15)), bit32.bor(1, self.state))
	t = bit32.bxor(bit32.bor(0, t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(61, t))), t)
	return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
end

-- Integer in [min, max].
function Rng.integer(self: Rng, min: number, max: number): number
	return min + math.floor(self:next() * (max - min + 1))
end

-- Picks a key from `order` using `weights[key]` (any positive scale).
function Rng.weighted(self: Rng, order: { string }, weights: { [string]: number }): string
	local total = 0
	for _, key in order do
		total += weights[key] or 0
	end
	local pick = self:next() * total
	for _, key in order do
		pick -= weights[key] or 0
		if pick < 0 then
			return key
		end
	end
	return order[#order]
end

return Rng
