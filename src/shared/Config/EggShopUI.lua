--!strict
-- Egg Shop carousel layout and feel (sizes in design px on the 900x540 canvas, times in seconds).
-- Balance (prices, odds, unlocks, taglines) lives in Eggs.lua, not here.

return {
	panelWidth = 780,
	panelHeight = 404,
	cardWidth = 150, -- unscaled card; the focused card is scaled up
	cardHeight = 200,
	focusScale = 1.35,
	pitch = 190, -- center-to-center distance between cards (focused half + neighbor half + gap)
	neighborOpacity = 0.6, -- neighbors drawn at this opacity (a panel-colored veil on top)
	snapSeconds = 0.2, -- snap/step tween
	morphSeconds = 0.25, -- Cash <-> Gems card morph
	morphDip = 0.12, -- how far a card shrinks mid-morph
	flashSeconds = 0.5, -- unlock flash
	newRibbonVisits = 2, -- the NEW ribbon stays for this many more shop visits
	dragOvershoot = 0.35, -- how far (in cards) a drag may pull past either end
	arrowSize = 80, -- square: >= 44 px on the smallest phone (800x360, scale ~0.56)
	-- Desktop edge-hover auto-scroll (mouse only, never on touch): the outer `edgeZone` of the
	-- panel's width on each side steps one card every autoScrollOuter s at the very edge, slowing
	-- to every autoScrollInner s at the inner boundary of the zone.
	edgeZone = 0.15,
	autoScrollOuter = 0.6,
	autoScrollInner = 1.2,
}
