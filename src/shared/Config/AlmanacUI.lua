--!strict
-- Almanac panel layout (design px on the 900x540 canvas). The milestone numbers themselves are
-- Config/Game.almanacMilestones; this only says how the panel and its milestone track look.
-- Logic: shared/AlmanacTrack.lua (track math), client/UI/Almanac.lua (drawing).

return {
	panelWidth = 760,
	panelHeight = 480, -- panels stay <= 480 tall
	contentTop = 72, -- C.panel's default: content starts under the header
	contentPad = 16, -- C.panel's side/bottom padding around the content

	-- Milestone track, right under the title: a marker row (bar + markers), then a label row
	-- (labels, or the tooltip of a tapped marker).
	trackHeight = 54,
	markerRowHeight = 28, -- the bar runs through the middle of this row
	barHeight = 10,
	labelTop = 30, -- label row: from here to trackHeight
	-- The current segment (last passed milestone .. next one) takes this fraction of the bar; the
	-- later milestones are spread proportionally over the rest.
	segmentFraction = 0.28,
	-- Marker sides (squares turned 45 degrees: on screen they're side x 1.41 across).
	nextSize = 18, -- the big diamond at the end of the fill
	passedSize = 16, -- gold, with a check
	laterSize = 8, -- the later Gem milestones
	laterBigSize = 12, -- the later big ones (eggs, luck)
	markerOutline = 2,
	hitWidth = 40, -- tap target per marker: this wide (neighbors may share), the track's height

	-- Labels: GothamBlack at labelSize, raised so they never draw below minScreenPx on screen
	-- (small phones), up to maxLabelSize. Later labels that would collide drop their numbers
	-- ("🥚Toxic"), then fall back to icons ("🥚"), then hide (the tooltip still tells). Widths
	-- are estimated per character (em), generously, so estimated boxes cover the real text.
	labelSize = 13,
	minScreenPx = 11,
	maxLabelSize = 21,
	charEm = 0.74,
	spaceEm = 0.32,
	emojiEm = 1.3,
	labelGap = 8, -- min space between two labels (and a label and the tooltip)
	tooltipPad = 8, -- tooltip box: text + this on each side

	-- Under the track: tier tabs, the 6x2 species grid, the pager.
	tabsGap = 6, -- track -> tabs
	tabHeight = 40,
	gridGap = 6, -- tabs -> grid
	cellWidth = 110, -- 6 x 110 + 5 x 8 = 700 <= content width (728)
	cellHeight = 112,
	cellGap = 8,
	pagerHeight = 48,
}
