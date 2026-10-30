-- Almanac milestone track: milestone list from Config/Game, the current segment and fill, marker
-- positions, labels (no collisions, inside the track), passed flags and the tooltip.
return function(t)
	local Track = t.require("src/shared/AlmanacTrack")
	local Game = t.require("src/shared/Config/Game")
	local UI = t.require("src/shared/Config/AlmanacUI")
	local Mutants = t.require("src/shared/Config/Mutants")

	local TOTAL = 0
	for _ in Mutants.species do
		TOTAL += 1
	end
	local WIDTH = UI.panelWidth - 2 * UI.contentPad
	local every = Game.almanacMilestones.every
	local lastAt = (TOTAL // every) * every
	local FOUNDS = { 0, 5, 24, 25, 26, 99, 100, 101, 399, 400, 410 }
	-- Desktop label size, and the size small phones need (on-screen scale ~0.56).
	local FONTS = { UI.labelSize, Track.fontSize(0.559) }

	local function each(fn)
		for _, found in FOUNDS do
			for _, font in FONTS do
				fn(found, font, Track.layout(found, TOTAL, WIDTH, font))
			end
		end
	end

	return {
		["milestones: every 25 up to the species total, big ones from Config/Game"] = function()
			local ms = Track.milestones(TOTAL)
			t.eq(#ms, lastAt // every)
			t.eq(ms[1].at, every)
			t.eq(ms[#ms].at, lastAt)
			for i, m in ms do
				t.eq(m.at, i * every)
				local big = Game.almanacMilestones.big[m.at]
				t.eq(m.big, big ~= nil, "big flag at " .. m.at)
				if not big then
					t.eq(m.kind, "gems")
					t.eq(m.gems, Game.almanacMilestones.gems)
				end
			end
			-- Never past the species total.
			t.eq(#Track.milestones(every - 1), 0)
			t.eq(#Track.milestones(2 * every), 2)
		end,
		["labels and tooltips read the rewards"] = function()
			local ms = Track.milestones(TOTAL)
			local byAt = {}
			for _, m in ms do
				byAt[m.at] = m
			end
			t.eq(Track.label(byAt[25]), "25 · 25 Gems")
			t.eq(Track.label(byAt[100]), "100 · Toxic Egg")
			t.eq(Track.label(byAt[200]), "200 · Void Egg")
			t.eq(Track.label(byAt[300]), "300 · Cosmic Egg")
			t.eq(Track.label(byAt[400]), "400 · +10% luck")
			t.eq(Track.label(byAt[100], "short"), "100")
			t.eq(Track.label(byAt[400], "short"), "400")
			t.eq(Track.parts(byAt[100]).pre, "100")
			t.eq(Track.parts(byAt[100]).post, "Toxic Egg")
			t.eq(Track.parts(byAt[25]).post, "25 Gems")
			t.eq(Track.parts(byAt[400], "short").post, "")
			t.eq(Track.tooltip(byAt[25]), "25 species: 25 Gems")
			t.eq(Track.tooltip(byAt[100]), "100 species: Toxic Egg")
			t.eq(Track.tooltip(byAt[400]), "400 species: +10% luck forever")
		end,
		["passed count, last/next milestone and fill fraction"] = function()
			local want = {
				[0] = { 0, nil, 25, 0 },
				[5] = { 0, nil, 25, 0.2 },
				[24] = { 0, nil, 25, 0.96 },
				[25] = { 1, 25, 50, 0 },
				[26] = { 1, 25, 50, 0.04 },
				[99] = { 3, 75, 100, 0.96 },
				[100] = { 4, 100, 125, 0 },
				[101] = { 4, 100, 125, 0.04 },
				[399] = { 15, 375, 400, 0.96 },
			}
			for found, w in want do
				local l = Track.layout(found, TOTAL, WIDTH, UI.labelSize)
				t.eq(l.passed, w[1], "passed at " .. found)
				t.eq(l.last and l.last.at, w[2], "last at " .. found)
				t.eq(l.next and l.next.at, w[3], "next at " .. found)
				t.near(l.fraction, w[4], 1e-9, "fraction at " .. found)
				t.ok(not l.allPassed, "not all passed at " .. found)
				t.near(l.fillWidth, w[4] * (l.segEnd - l.segStart), 1e-9)
			end
			for _, found in { 400, 410 } do
				local l = Track.layout(found, TOTAL, WIDTH, UI.labelSize)
				t.ok(l.allPassed, "all passed at " .. found)
				t.eq(l.next, nil)
				t.eq(l.fraction, 1)
				t.eq(l.fillWidth, l.barRight - l.barLeft)
			end
		end,
		["markers: every passed one gold on the left, next at the segment end, later proportional"] = function()
			each(function(found, _, l)
				local roles = { passed = 0, next = 0, later = 0 }
				for _, mk in l.markers do
					roles[mk.role] += 1
					t.ok(mk.x - mk.extent / 2 >= -1e-6, "marker inside the track (left) at " .. found)
					t.ok(mk.x + mk.extent / 2 <= WIDTH + 1e-6, "marker inside the track (right) at " .. found)
				end
				if l.allPassed then
					t.eq(roles.passed, #l.milestones)
					t.eq(#l.markers, #l.milestones)
					return
				end
				t.eq(roles.passed, l.passed, "every passed milestone drawn at " .. found)
				t.eq(roles.next, 1)
				t.eq(roles.later, #l.milestones - l.passed - 1)
				for _, mk in l.markers do
					if mk.role == "passed" then
						-- Proportional over the passed stretch; the last passed one at the segment's start.
						local p = mk.milestone.at / (l.last :: any).at
						t.near(mk.x, l.barLeft + p * (l.segStart - l.barLeft), 1e-6)
					elseif mk.role == "next" then
						t.eq(mk.x, l.segEnd)
					else
						-- Proportional over the rest of the bar.
						local p = (mk.milestone.at - l.next.at) / (lastAt - l.next.at)
						t.near(mk.x, l.segEnd + p * (l.barRight - l.segEnd), 1e-6)
					end
				end
				-- The segment takes its fixed fraction; the passed and later stretches share the rest by
				-- the species they cover.
				local span = l.barRight - l.barLeft
				t.near(l.segEnd - l.segStart, UI.segmentFraction * span, 1e-6)
				local doneRange, laterRange = l.last and l.last.at or 0, lastAt - l.next.at
				local other = (1 - UI.segmentFraction) * span
				t.near(l.segStart - l.barLeft, other * doneRange / (doneRange + laterRange), 1e-6)
			end)
		end,
		["no two markers overlap"] = function()
			each(function(found, _, l)
				local ms = table.clone(l.markers)
				table.sort(ms, function(a, b)
					return a.x < b.x
				end)
				for i = 2, #ms do
					local a, b = ms[i - 1], ms[i]
					t.ok(
						b.x - a.x >= (a.extent + b.extent) / 2,
						string.format("markers %d/%d overlap at %d", a.milestone.at, b.milestone.at, found)
					)
				end
			end)
		end,
		["labels: next always, big later ones if they fit, never colliding, inside the track"] = function()
			each(function(found, font, l)
				local labels = {}
				for _, mk in l.markers do
					if mk.role == "next" then
						t.ok(mk.label and not mk.label.short, "next milestone labeled in full at " .. found)
						t.eq(mk.label.text, Track.label(mk.milestone))
					end
					if mk.role == "later" and not mk.milestone.big then
						t.eq(mk.label, nil, "small later markers have no label")
					end
					if mk.label then
						t.ok(mk.label.x >= 0 and mk.label.x + mk.label.w <= WIDTH, "label inside at " .. found)
						-- Centered exactly on its marker (never slid toward a neighbour).
						t.ok(
							math.abs(mk.label.x + mk.label.w / 2 - mk.x) < 1e-6,
							string.format(
								"label '%s' centered on its marker at %d (font %d)",
								mk.label.text,
								found,
								font
							)
						)
						table.insert(labels, mk.label)
					end
				end
				for i = 1, #labels do
					for j = i + 1, #labels do
						local a, b = labels[i], labels[j]
						t.ok(
							a.x + a.w + UI.labelGap <= b.x or b.x + b.w + UI.labelGap <= a.x,
							string.format("labels '%s' and '%s' collide at %d (font %d)", a.text, b.text, found, font)
						)
					end
				end
			end)
		end,
		["big later labels: in full unless the next label is in the way, then the number, then none"] = function()
			local function shown(found, font)
				local out = {}
				for _, mk in Track.layout(found, TOTAL, WIDTH, font).markers do
					out[mk.milestone.at] = if mk.label then mk.label.text else false
				end
				return out
			end
			local full = {
				[100] = "100 · Toxic Egg",
				[200] = "200 · Void Egg",
				[300] = "300 · Cosmic Egg",
				[400] = "400 · +10% luck",
			}
			-- Desktop, the next milestone well clear of every big one: all four in full.
			for _, found in { 0, 5, 24, 99, 101, 175, 399 } do
				local s = shown(found, UI.labelSize)
				for at, text in full do
					if at > found then
						t.eq(s[at], text, string.format("desktop label %d at %d found", at, found))
					end
				end
			end
			-- The next one 50 species before a big one: the big one keeps its number, centered.
			t.eq(shown(26, UI.labelSize)[100], "100")
			-- 25 before: not even the number fits beside the next label; the tooltip still tells.
			t.eq(shown(60, UI.labelSize)[100], false)
			t.eq(shown(60, UI.labelSize)[75], "75 · 25 Gems")
			-- Small phones (bigger font): the rest still in full.
			local s = shown(5, Track.fontSize(0.559))
			t.eq(s[25], "25 · 25 Gems")
			t.eq(s[100], "100")
			t.eq(s[200], full[200])
			t.eq(s[300], full[300])
			t.eq(s[400], full[400])
		end,
		["tap targets: nearest marker, no overlaps, at least the marker, capped"] = function()
			for _, hit in { UI.hitWidth, 80 } do
				each(function(found, _, _)
					local l = Track.layout(found, TOTAL, WIDTH, UI.labelSize, nil, hit)
					local ms = table.clone(l.markers)
					table.sort(ms, function(a, b)
						return a.x < b.x
					end)
					for i, mk in ms do
						t.ok(mk.hitLeft >= 0 and mk.hitRight <= WIDTH, "tap target inside at " .. found)
						t.ok(mk.hitLeft <= mk.x - mk.extent / 2 + 1e-6, "tap target covers the marker (left)")
						t.ok(mk.hitRight >= mk.x + mk.extent / 2 - 1e-6, "tap target covers the marker (right)")
						t.ok(mk.hitRight - mk.hitLeft <= math.max(hit, mk.extent) + 1e-6, "tap target capped")
						if i > 1 then
							t.ok(mk.hitLeft >= ms[i - 1].hitRight - 1e-6, "tap targets overlap at " .. found)
						end
					end
				end)
			end
			-- Wide where there's room: the next diamond with 5 found gets the whole cap.
			local l = Track.layout(5, TOTAL, WIDTH, UI.labelSize, nil, 80)
			for _, mk in l.markers do
				if mk.role == "next" then
					t.near(mk.hitRight - mk.hitLeft, (mk.x - mk.hitLeft) + (mk.hitRight - mk.x), 1e-9)
					t.near(mk.x - mk.hitLeft, 40, 1e-9)
				end
			end
		end,
		["font: at least minScreenPx on screen, capped"] = function()
			for _, s in { 0.559, 0.587, 0.615, 1, 1.25 } do
				local f = Track.fontSize(s)
				t.ok(f * s >= UI.minScreenPx or f == UI.maxLabelSize, "font at scale " .. s)
				t.ok(f >= UI.labelSize and f <= UI.maxLabelSize)
			end
			t.eq(Track.fontSize(1), UI.labelSize)
		end,
		["tooltip: on the tapped marker, inside the track, covers the labels under it"] = function()
			local l = Track.layout(26, TOTAL, WIDTH, UI.labelSize, 100)
			t.ok(l.tooltip ~= nil, "tooltip for a later marker")
			t.eq(l.tooltip.text, "100 species: Toxic Egg")
			t.ok(l.tooltip.x >= 0 and l.tooltip.x + l.tooltip.w <= WIDTH)
			for _, mk in l.markers do
				if mk.label and not mk.label.covered then
					local a, b = mk.label, l.tooltip
					t.ok(
						a.x + a.w + UI.labelGap <= b.x or b.x + b.w + UI.labelGap <= a.x,
						"visible label under the tooltip"
					)
				end
			end
			-- At the right end it stays inside the track.
			local r = Track.layout(26, TOTAL, WIDTH, Track.fontSize(0.559), 400)
			t.ok(r.tooltip and r.tooltip.x + r.tooltip.w <= WIDTH, "400 tooltip inside")
			-- A passed milestone has its marker too: tapping it shows its reward.
			local passedTip = Track.layout(101, TOTAL, WIDTH, UI.labelSize, 25).tooltip
			t.ok(passedTip and passedTip.at == 25, "tooltip for a passed milestone")
			-- No marker for a milestone that doesn't exist -> no tooltip.
			t.eq(Track.layout(101, TOTAL, WIDTH, UI.labelSize, 30).tooltip, nil)
		end,
	}
end
