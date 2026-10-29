--!strict
-- The Almanac's milestone track (pure math + labels; client/UI/Almanac.lua draws it).
--
-- Milestones come from Config/Game.almanacMilestones: every `every` species found pays `gems`
-- Gems, except the `big` ones (eggs, or permanent luck), up to the last multiple of `every` not
-- above the species total. The track shows:
--   * the current segment (last passed milestone .. next one) on the left `segmentFraction` of the
--     bar, with the fill growing inside it from the last passed milestone (a gold check marker at
--     the left end) to the next one (the big diamond at the segment's right end);
--   * the later milestones spread proportionally over the rest of the bar, small, labeled only
--     when they're big (eggs, luck);
--   * when every milestone is passed, all of them, gold, spread over the whole (gold) bar.
-- Labels sit in a row under the markers. Their widths are estimated (Config/AlmanacUI em widths)
-- so they can be placed without measuring text: the later big labels are packed sideways (each
-- still spanning its marker) to fit in full; if they can't, they all drop to "100🥚", then to icons,
-- and an icon that still collides hides. A tapped marker's tooltip takes the label row and hides
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
	text: string,
	x: number, -- left edge (track px)
	w: number,
	short: boolean, -- collapsed to its icon
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

function AlmanacTrack.icon(m: Milestone): string
	return if m.kind == "luck" then "🍀" elseif m.kind == "egg" then "🥚" else "💎"
end

export type Form = "full" | "short" | "icon"

-- The marker's label: "full" = "25 💎25", "100 🥚Toxic", "400 🍀+10% luck"; "short" is the number
-- and the icon ("100🥚"); "icon" is just the icon ("🥚").
function AlmanacTrack.label(m: Milestone, form: Form?): string
	local icon = AlmanacTrack.icon(m)
	if form == "icon" then
		return icon
	end
	local reward = if m.kind == "luck"
		then percent(m.luck :: number) .. " luck"
		elseif m.kind == "egg" then m.egg :: string
		else tostring(m.gems)
	if form == "short" then
		return tostring(m.at) .. icon
	end
	return string.format("%d %s%s", m.at, icon, reward)
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

-- Packs labels (in marker order, each { w, center }) into [wall, width] with labelGap between
-- them, each spanning its marker's center by labelInset, as close to centered as that allows.
-- Returns the left edges, or nil when they can't all fit.
local function pack(items: { { w: number, center: number } }, wall: number, width: number): { number }?
	local gap, inset = UIConfig.labelGap, UIConfig.labelInset
	local lo, hi, xs = {}, {}, {}
	for i, it in items do
		local reach = math.min(inset, it.w / 2)
		lo[i] = math.max(wall, it.center + reach - it.w)
		hi[i] = math.min(width - it.w, it.center - reach)
		if lo[i] > hi[i] + 1e-6 then
			return nil
		end
		xs[i] = math.clamp(it.center - it.w / 2, lo[i], hi[i])
	end
	-- Push right past each left neighbour, then pull left before each right neighbour.
	for i = 2, #items do
		xs[i] = math.max(xs[i], xs[i - 1] + items[i - 1].w + gap)
	end
	for i = #items, 1, -1 do
		xs[i] = math.min(xs[i], hi[i], if i < #items then xs[i + 1] - gap - items[i].w else math.huge)
	end
	for i in items do
		if xs[i] < lo[i] - 1e-6 or (i > 1 and xs[i] < xs[i - 1] + items[i - 1].w + gap - 1e-6) then
			return nil
		end
	end
	return xs
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
	local pad = math.ceil(AlmanacTrack.extent(UIConfig.nextSize) / 2)
	local barLeft, barRight = pad, width - pad
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
		local hasLater = passed + 2 <= #ms
		segStart = barLeft
		segEnd = if hasLater then barLeft + UIConfig.segmentFraction * span else barRight
		fraction = math.clamp((found - fromAt) / (next.at - fromAt), 0, 1)
		if last then
			add(last, segStart, "passed")
		end
		add(next, segEnd, "next")
		local lastAt = ms[#ms].at
		for i = passed + 2, #ms do
			local m = ms[i]
			add(m, segEnd + (m.at - next.at) / (lastAt - next.at) * (barRight - segEnd), "later")
		end
	end

	-- Labels, by priority: the next milestone (always, in full), the last passed one (its number,
	-- at the left end), then the big later ones in one form for all: in full if they pack, else
	-- "100🥚", else icons (centered; any icon that still collides hides).
	local placed: { Label } = {}
	local function make(text: string, center: number, short: boolean): Label
		local w = AlmanacTrack.textWidth(text, font)
		return { text = text, x = boxAt(center, w, width), w = w, short = short, covered = false }
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
			mk.label = make(AlmanacTrack.label(mk.milestone), mk.x, false)
			table.insert(placed, mk.label :: Label)
		end
	end
	for _, mk in markers do
		if mk.role == "passed" and not allPassed then
			local l = make(tostring(mk.milestone.at), mk.x, false)
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
	-- The fixed labels (next, last passed) all sit left of the later markers: a wall to pack from.
	local wall = 0
	for _, p in placed do
		wall = math.max(wall, p.x + p.w + UIConfig.labelGap)
	end
	local done = false
	for _, form: Form in { "full", "short" } do
		local items = {}
		for _, mk in rest do
			local text = AlmanacTrack.label(mk.milestone, form)
			table.insert(items, { text = text, w = AlmanacTrack.textWidth(text, font), center = mk.x })
		end
		local xs = pack(items, wall, width)
		if xs then
			for i, mk in rest do
				local l: Label = { text = items[i].text, x = xs[i], w = items[i].w, short = false, covered = false }
				mk.label = l
				table.insert(placed, l)
			end
			done = true
			break
		end
	end
	if not done then
		for _, mk in rest do
			local l = make(AlmanacTrack.label(mk.milestone, "icon"), mk.x, true)
			if fits(l, placed) then
				mk.label = l
				table.insert(placed, l)
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
