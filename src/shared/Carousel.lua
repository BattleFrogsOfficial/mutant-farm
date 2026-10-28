--!strict
-- The Egg Shop carousel's decisions, as pure functions (the UI animates what these return; the
-- tests check them headlessly). Cards are 1..count; card i is centered when the strip's offset is
-- (i - 1) * pitch. Some cards can't take focus (further-locked tiers): input never settles there.

local Carousel = {}

function Carousel.offsetOf(index: number, pitch: number): number
	return (index - 1) * pitch
end

-- The card nearest to the strip center at `offset`.
function Carousel.nearest(offset: number, pitch: number, count: number): number
	return math.clamp(math.floor(offset / pitch + 0.5) + 1, 1, count)
end

-- First focusable card from `from` (inclusive) moving `dir`, or nil.
local function scan(from: number, dir: number, count: number, focusable: (number) -> boolean): number?
	local i = from
	while i >= 1 and i <= count do
		if focusable(i) then
			return i
		end
		i += dir
	end
	return nil
end

-- Where a drag settles on release: the nearest card, or if it can't take focus the nearest
-- focusable card in the direction of travel (dir +1/-1, 0 = none), else back the other way.
function Carousel.settle(
	offset: number,
	pitch: number,
	count: number,
	focusable: (number) -> boolean,
	dir: number
): number
	local i = Carousel.nearest(offset, pitch, count)
	if focusable(i) then
		return i
	end
	local d = if dir ~= 0 then dir else -1
	return scan(i, d, count, focusable) or scan(i, -d, count, focusable) or 1
end

-- One step (arrow, key, wheel notch, auto-scroll): the next focusable card that way, or stay.
function Carousel.step(index: number, dir: number, count: number, focusable: (number) -> boolean): number
	return scan(index + dir, dir, count, focusable) or index
end

-- Mouse wheel: one card per notch (Position.Z > 0 is "up" = left).
function Carousel.wheel(index: number, wheelZ: number, count: number, focusable: (number) -> boolean): number
	if wheelZ == 0 then
		return index
	end
	return Carousel.step(index, if wheelZ > 0 then -1 else 1, count, focusable)
end

-- While dragging the strip follows the pointer, with a little give past either end.
function Carousel.clampDrag(offset: number, pitch: number, count: number, overshoot: number): number
	return math.clamp(offset, -overshoot * pitch, (count - 1 + overshoot) * pitch)
end

-- Desktop edge-hover auto-scroll. `fraction` is the mouse x across the panel (0..1). Returns the
-- direction (0 = none) and the step interval. Never on touch devices, never outside the panel.
function Carousel.autoScroll(
	cfg: { edgeZone: number, autoScrollOuter: number, autoScrollInner: number },
	fraction: number,
	inside: boolean,
	mouseEnabled: boolean,
	touchEnabled: boolean
): (number, number?)
	if not mouseEnabled or touchEnabled or not inside then
		return 0, nil
	end
	local zone = cfg.edgeZone
	local dir, depth
	if fraction < zone then
		dir, depth = -1, (zone - fraction) / zone
	elseif fraction > 1 - zone then
		dir, depth = 1, (fraction - (1 - zone)) / zone
	else
		return 0, nil
	end
	depth = math.clamp(depth, 0, 1)
	return dir, cfg.autoScrollInner + (cfg.autoScrollOuter - cfg.autoScrollInner) * depth
end

-- The cards whose centers are within `tolerance` px of the strip center.
function Carousel.centered(offset: number, pitch: number, count: number, tolerance: number): { number }
	local out = {}
	for i = 1, count do
		if math.abs(Carousel.offsetOf(i, pitch) - offset) <= tolerance then
			table.insert(out, i)
		end
	end
	return out
end

return Carousel
