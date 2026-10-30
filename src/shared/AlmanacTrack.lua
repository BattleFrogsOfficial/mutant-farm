--!strict
-- The Almanac's milestone track (pure math + labels; client/UI/Almanac.lua draws it).
--
-- Milestones come from Config/Game.almanacMilestones: every `every` species found pays `gems`
-- Gems, except the `big` ones (eggs, or permanent luck), up to the last multiple of `every` not
-- above the species total. The track shows:
--   * every passed milestone gold with a check, spread proportionally over a gold stretch at the
--     left end (0 .. the last passed one; only the last passed one is labeled);
--   * the current segment (last passed milestone .. next one) on `segmentFraction` of the bar,
--     with the fill growing inside it to the next milestone (the big diamond at its right end);
--   * the later milestones spread proportionally over the rest, small, labeled only when they're
--     big (eggs, luck). The passed and later stretches share what the segment leaves, in
--     proportion to the species counts they cover;
--   * when every milestone is passed, all of them, gold, spread over the whole (gold) bar.
-- Labels sit in a row under the markers, each centered exactly on its marker (never slid sideways:
-- a label off its diamond reads as belonging to the neighbour). Their widths are estimated
-- (Config/AlmanacUI em widths) so they can be placed without measuring text; the bar's ends are
-- inset so the first and last labels fit centered. A big label that would collide with one already
-- placed drops to its number alone ("100"), and hides if even that collides. A tapped marker's tooltip takes the label row and hides
-- the labels it covers. Each marker also gets a tap target: the stretch of track nearer to it than
-- to its neighbours, capped (Config/AlmanacUI.hitWidth / minTapScreenPx).

local GameConfig = require(script.Parent.Config.Game)
local UIConfig = require(script.Parent.Config.AlmanacUI)

export type Milestone = {
	at: number,
	kind: "gems" | "egg" | "luck",
	gems: number?,
	egg: string?,
	luck: number?,
	big: boolean,
}

export type Label = {
	text: string, -- plain words ("100 · Toxic Egg")
	pre: string, -- top line: the species needed
	glyph: string?, -- (unused: labels are words only)
	post: string, -- second line: the reward ("" when collapsed to the number)
	x: number, -- left edge (track px)
	w: number,
	short: boolean, -- collapsed to the number alone
	covered: boolean, -- under the open tooltip (not drawn)
}

export type Marker = {
	milestone: Milestone,
	x: number, -- center (track px)
	role: "passed" | "next" | "later",
	size: number, -- side of the square (drawn turned 45 degrees)
	outline: number, -- ink outline (outside the square)
	extent: number, -- width/height on screen (diagonal of the outlined square)
	hitLeft: number, -- tap target (track px)
	hitRight: number,
	label: Label?,
}

export type Layout = {
	milestones: { Milestone },
	passed: number, -- how many milestones are passed
	allPassed: boolean,
	last: Milestone?, -- last passed
	next: Milestone?,
	fraction: number, -- 0..1 of the current segment (1 when all passed)
	barLeft: number,
	barRight: number,
	segStart: number,
	segEnd: number,
	fillWidth: number,
	markers: { Marker },
	tooltip: { at: number, text: string, x: number, w: number }?,
}

local AlmanacTrack = {}

local SQRT2 = math.sqrt(2)

-- Every milestone up to `total` species, in order.
function AlmanacTrack.milestones(total: number, cfg: any?): { Milestone }
	local c = cfg or GameConfig.almanacMilestones
	local out = {}
	local at = c.every
	while at <= total do
		local big = c.big[at]
		if big and big.luck then
			table.insert(out, { at = at, kind = "luck", luck = big.luck, big = true } :: Milestone)
		elseif big and big.eggs then
			-- One egg tier per big milestone (the first, alphabetically, if a config ever lists more).
			local ids = {}
			for id in big.eggs do
				table.insert(ids, id)
			end
			table.sort(ids)
			table.insert(out, { at = at, kind = "egg", egg = ids[1], big = true } :: Milestone)
		else
			table.insert(out, { at = at, kind = "gems", gems = c.gems, big = false } :: Milestone)
		end
		at += c.every
	end
	return out
end

local function percent(luck: number): string
	return string.format("+%d%%", math.floor(luck * 100 + 0.5))
end

export type Form = "full" | "short"
export type Parts = { pre: string, glyph: string?, post: string }

-- The reward, in words: "25 Gems", "Toxic Egg", "+10% luck".
function AlmanacTrack.reward(m: Milestone): string
	return if m.kind == "luck"
		then percent(m.luck :: number) .. " luck"
		elseif m.kind == "egg" then (m.egg :: string) .. " Egg"
		else string.format("%d Gems", m.gems :: number)
end

-- The marker's label, two lines stacked: the requirement on top ("100", species found) and the
-- reward under it ("Toxic Egg", at rewardScale of the font). "short" is the number alone.
function AlmanacTrack.parts(m: Milestone, form: Form?): Parts
	if form == "short" then
		return { pre = tostring(m.at), post = "" }
	end
	return { pre = tostring(m.at), post = AlmanacTrack.reward(m) }
end

-- The label in plain words: "100 · Toxic Egg", or "100".
function AlmanacTrack.label(m: Milestone, form: Form?): string
	local p = AlmanacTrack.parts(m, form)
	return if p.post ~= "" then p.pre .. " · " .. p.post else p.pre
end

-- The reward line's font for a label `font`.
function AlmanacTrack.rewardFont(font: number): number
	return math.floor(font * UIConfig.rewardScale + 0.5)
end

-- Estimated drawn width of a label: its wider line.
function AlmanacTrack.partsWidth(p: Parts, font: number): number
	return math.max(AlmanacTrack.textWidth(p.pre, font), AlmanacTrack.textWidth(p.post, AlmanacTrack.rewardFont(font)))
end

-- The tooltip shown when a marker is tapped.
function AlmanacTrack.tooltip(m: Milestone): string
	local reward = if m.kind == "luck"
		then percent(m.luck :: number) .. " luck forever"
		elseif m.kind == "egg" then (m.egg :: string) .. " Egg"
		else string.format("%d Gems", m.gems :: number)
	return string.format("%d species: %s", m.at, reward)
end

-- Estimated drawn width of `text` at `font` px (generous: never narrower than the real text).
function AlmanacTrack.textWidth(text: string, font: number): number
	local w = 0
	for _, cp in utf8.codes(text) do
		if cp >= 0x2000 then
			w += UIConfig.emojiEm * font
		elseif cp == 32 then
			w += UIConfig.spaceEm * font
		elseif UIConfig.charEms[utf8.char(cp)] then
			w += UIConfig.charEms[utf8.char(cp)] * font
		elseif cp >= 65 and cp <= 90 then -- capitals
			w += UIConfig.capEm * font
		else
			w += UIConfig.charEm * font
		end
	end
	return math.ceil(w)
end

-- Label font (design px) for an on-screen scale (HUD scale x panel fit): labelSize, raised so it
-- draws at least minScreenPx on screen, capped at maxLabelSize.
function AlmanacTrack.fontSize(screenScale: number): number
	local need = math.ceil(UIConfig.minScreenPx / math.max(screenScale, 0.01))
	return math.clamp(math.max(UIConfig.labelSize, need), UIConfig.labelSize, UIConfig.maxLabelSize)
end

-- Space a marker takes on screen: the diagonal of its square with the outline around it.
function AlmanacTrack.extent(size: number, outline: number?): number
	return (size + 2 * (outline or UIConfig.markerOutline)) * SQRT2
end

local function overlaps(a: Label, b: { x: number, w: number }, gap: number): boolean
	return a.x < b.x + b.w + gap and b.x < a.x + a.w + gap
end

local function boxAt(center: number, w: number, width: number): number
	return math.clamp(center - w / 2, 0, math.max(0, width - w))
end

-- Track layout for `found` species out of `total`, on a track `width` px wide, with labels at
-- `font` px. `tip` = the milestone whose tooltip is open (if it has a marker).
-- `hit` = the widest tap target (design px; default Config hitWidth), for small screens.
function AlmanacTrack.layout(
	found: number,
	total: number,
	width: number,
	font: number,
	tip: number?,
	hit: number?
): Layout
	local ms = AlmanacTrack.milestones(total)
	local passed = 0
	for _, m in ms do
		if found >= m.at then
			passed += 1
		end
	end
	local allPassed = passed == #ms
	local last = ms[passed]
	local nextM = ms[passed + 1]
	-- The bar's ends: room for the big diamond, and for the label of the end marker centered on
	-- it (the first milestone shows its full label only while it's the next one; once passed, its
	-- number at most; the last one always has its full label).
	local pad = math.ceil(AlmanacTrack.extent(UIConfig.nextSize) / 2)
	local function endPad(m: Milestone?, form: Form): number
		if not m then
			return pad
		end
		return math.max(pad, math.ceil(AlmanacTrack.partsWidth(AlmanacTrack.parts(m, form), font) / 2))
	end
	local first = ms[1]
	local barLeft = endPad(first, if first and found < first.at then "full" else "short")
	local barRight = width - endPad(ms[#ms], "full")
	local span = barRight - barLeft

	local markers: { Marker } = {}
	local function add(m: Milestone, x: number, role: "passed" | "next" | "later")
		local size = if role == "passed"
			then UIConfig.passedSize
			elseif role == "next" then UIConfig.nextSize
			elseif m.big then UIConfig.laterBigSize
			else UIConfig.laterSize
		local outline = if role == "later" and not m.big then UIConfig.laterOutline else UIConfig.markerOutline
		table.insert(markers, {
			milestone = m,
			x = x,
			role = role,
			size = size,
			outline = outline,
			extent = AlmanacTrack.extent(size, outline),
			hitLeft = x,
			hitRight = x,
		})
	end

	local segStart, segEnd, fraction
	if allPassed then
		segStart, segEnd, fraction = barLeft, barRight, 1
		local lastAt = if #ms > 0 then ms[#ms].at else 1
		for _, m in ms do
			add(m, barLeft + m.at / lastAt * span, "passed")
		end
	else
		local next = nextM :: Milestone
		local fromAt = if last then last.at else 0
		local lastAt = ms[#ms].at
		-- The passed stretch (0 .. last passed) and the later one (next .. last milestone) share
		-- what the segment leaves, in proportion to the species they cover.
		local doneRange, laterRange = fromAt, lastAt - next.at
		local other = if doneRange + laterRange > 0 then (1 - UIConfig.segmentFraction) * span else 0
		local doneW = if other > 0 then other * doneRange / (doneRange + laterRange) else 0
		segStart = barLeft + doneW
		segEnd = barRight - (other - doneW)
		fraction = math.clamp((found - fromAt) / (next.at - fromAt), 0, 1)
		for i = 1, passed do
			add(ms[i], barLeft + ms[i].at / fromAt * doneW, "passed")
		end
		add(next, segEnd, "next")
		for i = passed + 2, #ms do
			local m = ms[i]
			add(m, segEnd + (m.at - next.at) / laterRange * (barRight - segEnd), "later")
		end
	end

	-- Labels, each centered on its marker, by priority: the next milestone (always, in full), the
	-- last passed one (its number, at the segment's start; earlier passed ones stay unlabeled), then
	-- the big later ones left to right: in full if that fits beside the labels already placed, else
	-- the number alone, else none (the tooltip still tells).
	local placed: { Label } = {}
	local function make(p: Parts, center: number, short: boolean): Label
		local w = AlmanacTrack.partsWidth(p, font)
		local text = if p.post ~= "" then p.pre .. " · " .. p.post else p.pre
		return {
			text = text,
			pre = p.pre,
			glyph = p.glyph,
			post = p.post,
			x = boxAt(center, w, width),
			w = w,
			short = short,
			covered = false,
		}
	end
	local function fits(l: Label, others: { Label }): boolean
		for _, p in others do
			if overlaps(l, p, UIConfig.labelGap) then
				return false
			end
		end
		return true
	end
	local rest: { Marker } = {}
	for _, mk in markers do
		if mk.role == "next" then
			mk.label = make(AlmanacTrack.parts(mk.milestone), mk.x, false)
			table.insert(placed, mk.label :: Label)
		end
	end
	for _, mk in markers do
		if mk.role == "passed" and not allPassed then
			if mk.milestone ~= last then
				continue
			end
			local l = make({ pre = tostring(mk.milestone.at), post = "" }, mk.x, false)
			if fits(l, placed) then
				mk.label = l
				table.insert(placed, l)
			end
		elseif mk.milestone.big and mk.role ~= "next" then
			table.insert(rest, mk)
		end
	end
	table.sort(rest, function(a, b)
		return a.x < b.x
	end)
	for _, mk in rest do
		for _, form: Form in { "full", "short" } do
			local l = make(AlmanacTrack.parts(mk.milestone, form), mk.x, form == "short")
			if fits(l, placed) then
				mk.label = l
				table.insert(placed, l)
				break
			end
		end
	end

	-- Tap targets: the stretch nearer to each marker than to its neighbours, at most `hit` wide.
	local half = (hit or UIConfig.hitWidth) / 2
	local order = table.clone(markers)
	table.sort(order, function(a, b)
		return a.x < b.x
	end)
	for i, mk in order do
		local prev, nxt = order[i - 1], order[i + 1]
		-- Neighbours split the free space between their edges, so each target covers its marker.
		local left = if prev then (prev.x + prev.extent / 2 + mk.x - mk.extent / 2) / 2 else 0
		local right = if nxt then (mk.x + mk.extent / 2 + nxt.x - nxt.extent / 2) / 2 else width
		mk.hitLeft = math.max(left, math.min(mk.x - half, mk.x - mk.extent / 2))
		mk.hitRight = math.min(right, math.max(mk.x + half, mk.x + mk.extent / 2))
	end

	-- The open tooltip takes the label row under its marker and covers the labels it overlaps.
	local tooltip = nil
	if tip then
		for _, mk in markers do
			if mk.milestone.at == tip then
				local text = AlmanacTrack.tooltip(mk.milestone)
				local w = AlmanacTrack.textWidth(text, font) + 2 * UIConfig.tooltipPad
				tooltip = { at = tip, text = text, x = boxAt(mk.x, w, width), w = w }
				break
			end
		end
	end
	if tooltip then
		for _, mk in markers do
			local l = mk.label
			if l and overlaps(l, tooltip, UIConfig.labelGap) then
				l.covered = true
			end
		end
	end

	return {
		milestones = ms,
		passed = passed,
		allPassed = allPassed,
		last = last,
		next = nextM,
		fraction = fraction,
		barLeft = barLeft,
		barRight = barRight,
		segStart = segStart,
		segEnd = segEnd,
		fillWidth = fraction * (segEnd - segStart),
		markers = markers,
		tooltip = tooltip,
	}
end

return AlmanacTrack
