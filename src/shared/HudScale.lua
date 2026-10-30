--!strict
-- The HUD's design-to-pixel scale: the shorter edge of the area the GUI covers (below Roblox's top
-- bar) against Config/Hud.designHeight, but never so large that the design canvas gets narrower
-- than designWidth (a 4:3 or docked window would squeeze the 900-wide layout into overlaps) or
-- that the top-center Cash panel reaches into Roblox's top-left chat window, then clamped to
-- [minScale, maxScale] (maxScaleTouch on touch devices). UIController applies it; the UI preview
-- (ui-export / ui-render) uses the same numbers.

local Hud = require(script.Parent.Config.Hud)

local HudScale = {}

-- Design px from the canvas's middle to Cash's drawn left edge (its ink outline included).
local CASH_LEFT = Hud.top.cashWidth / 2 - Hud.top.cashX + Hud.faceOutline

function HudScale.of(width: number, height: number, touch: boolean): number
	local s = math.min(math.min(width, height) / Hud.designHeight, width / Hud.designWidth)
	local chat = math.min(Hud.top.chatWidth, width * Hud.top.chatFraction)
	s = math.min(s, (width / 2 - chat) / CASH_LEFT)
	return math.clamp(s, Hud.minScale, if touch then Hud.maxScaleTouch else Hud.maxScale)
end

return HudScale
