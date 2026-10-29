--!strict
-- HUD layout numbers (design px on the 900x540 canvas; the whole HUD is scaled by one UIScale).
-- Logic and UI read these; tuning the layout never edits Hud.lua.

return {
	-- Scaling (shared/HudScale.lua): the HUD scales with the SHORTER screen edge against the
	-- design height, capped so big monitors don't get a giant HUD (touch screens stay at 1:1).
	designWidth = 900,
	designHeight = 540,
	minScale = 0.5,
	maxScale = 1.25, -- mouse/keyboard screens
	maxScaleTouch = 1.0, -- phones and tablets
	-- Panels are sized to their content; one wider/taller than the design canvas (a narrow window
	-- at the 1.25x cap) shrinks to fit, keeping this much space to the canvas edge.
	panelMargin = 12,
}
