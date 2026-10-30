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
	trackHeight = 76,
	-- The bar runs through the middle of this row, tall enough for the big diamond with its
	-- outline (18 px side, ~25 px across + ~4 px of outline at each tip).
	markerRowHeight = 34,
	barHeight = 10,
	labelTop = 36, -- label row (two lines): from here to trackHeight
	-- The current segment (last passed milestone .. next one) takes this fraction of the bar; the
	-- later milestones are spread proportionally over the rest.
	segmentFraction = 0.28,
	-- Marker sides (squares turned 45 degrees: on screen they're side x 1.41 across).
	nextSize = 18, -- the big diamond at the end of the fill
	passedSize = 16, -- gold, with a check
	laterSize = 8, -- the later Gem milestones
	laterBigSize = 12, -- the later big ones (eggs, luck)
	-- Ink outlines: 3 px (the boxy rule) on the bar and every marker except the tiny later Gem
	-- ones, where 3 px would swallow an 8 px square; those keep 2 px.
	barOutline = 3,
	markerOutline = 3,
	laterOutline = 2,
	-- Marker colors: passed gold, next blue (Theme). Later egg milestones use their tier's swatch
	-- lightened this much toward white (Void's near-black would vanish on the slate bar); the luck
	-- milestone has its own teal (Toxic's green is taken by the Toxic egg).
	eggMarkerTint = 0.4,
	luckColor = "#4AE0C8",
	-- Passed markers' check: two ink bars in a square this fraction of the marker's side, each
	-- { x, y (center, 0..1 of that square), length (0..1), rotation }.
	checkRatio = 0.7,
	checkThickness = 3,
	checkBars = {
		{ x = 0.28, y = 0.66, len = 0.38, angle = 45 },
		{ x = 0.62, y = 0.5, len = 0.74, angle = -49 },
	},
	-- Tap targets: each marker owns the stretch of track closer to it than to its neighbours (no
	-- overlaps, no gaps), up to half of max(hitWidth, minTapScreenPx on screen) on each side, the
	-- track's full height. Labels are tappable too (they open their own marker).
	hitWidth = 40,
	minTapScreenPx = 44,

	-- Labels: two lines under each labeled marker, the species needed on top ("100") and the
	-- reward under it ("Toxic Egg", at rewardScale of the font), GothamBlack (drawn as Montserrat
	-- Black) at labelSize, raised so they never draw below minScreenPx on screen (small phones), up
	-- to maxLabelSize (two lines fit the label row: trackHeight - labelTop). Every label is centered
	-- exactly on its marker (the bar's ends are inset to make room for the end labels); a big one
	-- that would come within labelGap of a label already placed drops to its number, then hides
	-- (the tooltip still tells). Widths are estimated per character in em of Montserrat Black
	-- (measured: lowercase and digits ~0.63, capitals ~0.75); the preview's Almanac check measures
	-- the drawn labels.
	labelSize = 16,
	minScreenPx = 11,
	maxLabelSize = 20,
	rewardScale = 0.875, -- 14 px under a 16 px number
	charEm = 0.64,
	capEm = 0.76,
	charEms = { ["·"] = 0.36, ["%"] = 0.93, M = 0.96, W = 1.2, m = 0.96, w = 0.9 },
	spaceEm = 0.3,
	emojiEm = 1.25,
	labelGap = 8, -- min space between two labels (and a label and the tooltip)
	tooltipPad = 8, -- tooltip box: text + this on each side
	tooltipOutline = 3,

	-- Under the track: tier tabs, the 6x2 species grid, the pager, 8 px apart as frames, so the
	-- outlines and shadows drawn outside them never touch (the picked tab's 4 px gold outline, the
	-- cards' shadows, the pager buttons' outlines). 76 + 8 + 42 + 8 + (2 x 97 + 8) + 8 + 48 = 392,
	-- the content height (480 - 72 - 16).
	tabsGap = 8, -- track -> tabs
	tabHeight = 42,
	-- A tab: the tier name on top, its found / total count on a smaller line under it, each at its
	-- full size (a 7th tab makes them 98 wide; text never shrinks to fit).
	tabTextInset = 7,
	tabName = { y = 2, height = 19, text = 17 },
	tabCount = { y = 21, height = 18, text = 16 },
	gridGap = 8, -- tabs -> grid
	cellWidth = 110, -- 6 x 110 + 5 x 8 = 700 <= content width (728)
	cellHeight = 97,
	cellGap = 8,
	pagerHeight = 48,
}
