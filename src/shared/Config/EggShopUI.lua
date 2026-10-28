--!strict
-- Egg Shop carousel layout and feel (sizes in design px on the 900x540 canvas, times in seconds).
-- Balance (prices, odds, unlocks, taglines) lives in Eggs.lua, not here.

return {
	panelWidth = 860,
	panelHeight = 470,
	cardWidth = 240, -- the focused card at full size
	cardHeight = 320,
	sideScale = 0.6, -- neighbors one pitch away are drawn at this scale (continuous in between)
	pitch = 216, -- center-to-center distance between cards (focused half + neighbor half + gap)
	neighborOpacity = 0.6, -- neighbors drawn at this opacity (a panel-colored veil on top)
	snapSeconds = 0.2, -- snap/step glide (ease-out; new input retargets mid-glide)
	flickSeconds = 0.12, -- a drag release projects this far ahead along its velocity
	tapSlop = 8, -- screen px a press may move and still count as a tap (tap a side card to focus it)
	morphSeconds = 0.25, -- Cash <-> Gems card morph
	morphDip = 0.12, -- how far a card shrinks mid-morph
	flashSeconds = 0.5, -- unlock flash
	newRibbonVisits = 2, -- the NEW ribbon stays for this many more shop visits
	dragOvershoot = 0.35, -- how far (in cards) a drag may pull past either end
	arrowSize = 80, -- square: >= 44 px on the smallest phone (800x360, scale ~0.56)
	-- Desktop edge-hover auto-scroll (mouse only, never on touch): the outer `edgeZone` of the
	-- strip's width on each side (not the arrow buttons) steps one card every autoScrollOuter s at
	-- the very edge, slowing to every autoScrollInner s at the inner boundary of the zone. Paused
	-- after any click/key/wheel until the mouse leaves the zone.
	edgeZone = 0.15,
	autoScrollOuter = 0.6,
	autoScrollInner = 1.2,
}
